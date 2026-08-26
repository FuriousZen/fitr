#!/usr/bin/env python
"""Measure backend latency at each tier.

    python scripts/benchmark.py --items 200 --reps 30
    python scripts/benchmark.py --items 1500 --reps 30 --json bench.json
    python scripts/benchmark.py --http http://127.0.0.1:8000 --items 200

What it measures
----------------
* CLIP inference, the two cache tiers, pgvector k-NN retrieval and the whole
  request path around them, on CPU.
* The Gemini call, only when a key is configured. Without one the heuristic
  ranker runs and the recommendation rows cover every stage except the LLM
  round trip; the output says which of the two it measured.
* Default mode drives the Flask test client in-process, which excludes HTTP
  framing, socket and WSGI-server overhead. Pass --http to measure a running
  server over loopback instead. Both are single-process, single-machine
  numbers for whatever host this runs on.

The script prints the hardware and versions it ran on alongside the numbers,
because a latency figure without them means nothing.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import platform
import statistics
import sys
import time
import uuid
from dataclasses import dataclass, field

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# The HuggingFace hub client logs an HTTP line per metadata request at INFO,
# which drowns the results. Set before importing the app.
os.environ.setdefault("FITR_LOG_LEVEL", "WARNING")
import logging  # noqa: E402

for _noisy in ("httpx", "huggingface_hub", "transformers", "filelock"):
    logging.getLogger(_noisy).setLevel(logging.WARNING)

from PIL import Image, ImageDraw  # noqa: E402

BENCH_USER_PREFIX = "bench-"


# ---------------------------------------------------------------- helpers ---


@dataclass
class Sample:
    name: str
    unit: str
    values: list[float] = field(default_factory=list)
    note: str = ""

    def add(self, value: float) -> None:
        self.values.append(value)

    @staticmethod
    def _pct(ordered: list[float], pct: float) -> float:
        rank = max(1, int(round(pct / 100.0 * len(ordered))))
        return ordered[min(rank, len(ordered)) - 1]

    def summary(self) -> dict:
        if not self.values:
            return {"name": self.name, "n": 0, "note": self.note or "no samples"}
        ordered = sorted(self.values)
        return {
            "name": self.name,
            "unit": self.unit,
            "n": len(ordered),
            "min": round(ordered[0], 2),
            "p50": round(self._pct(ordered, 50), 2),
            "p90": round(self._pct(ordered, 90), 2),
            "p95": round(self._pct(ordered, 95), 2),
            "max": round(ordered[-1], 2),
            "mean": round(statistics.fmean(ordered), 2),
            "note": self.note,
        }


def make_image(seed: int, salt: str = "", size=(384, 512)) -> bytes:
    """A distinct JPEG per (seed, salt).

    CLIP's cost depends on the input tensor shape, not the picture, so
    synthetic images give the same inference latency as photographs. They do
    NOT give meaningful recognition accuracy, and this script does not claim
    any.

    ``salt`` matters more than it looks. The L2 cache is content-addressed and
    lives in Postgres, so it survives between runs: without a per-run salt the
    second invocation of this script would find every "cold" image already
    cached and would silently measure the warm path while calling it cold. A
    fresh salt per run guarantees the cold measurements are genuinely cold.
    """
    # sha256, not hash(): Python's str hashing is randomised per process, so
    # hash() would make a run unreproducible even given the same salt.
    digest = hashlib.sha256(f"{salt}:{seed}".encode()).digest()

    def channel(index: int) -> int:
        return digest[index]

    img = Image.new("RGB", size, (240, 240, 240))
    draw = ImageDraw.Draw(img)
    draw.rectangle(
        [40, 60, size[0] - 40, size[1] - 60],
        fill=(channel(0), channel(1), channel(2)),
    )
    draw.ellipse(
        [80, 120, size[0] - 80, size[1] - 200],
        fill=(channel(3), channel(4), channel(5)),
    )
    # Drawn text guarantees the encoded bytes differ even if two colour
    # triples happen to collide.
    draw.text((10, 10), f"item-{seed}-{salt}", fill=(0, 0, 0))
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=88)
    return buf.getvalue()


TYPES = ["T-Shirt", "Shirt", "Sweater", "Jacket", "Coat", "Jeans", "Pants", "Shorts", "Shoes"]
VIBES = ["casual", "formal", "sporty", "cozy", "smart"]
CONDITIONS = ["Sunny", "Cloudy", "Rainy", "Snowy"]


def environment() -> dict:
    import torch

    import flask
    import sqlalchemy
    import transformers

    try:
        import importlib.metadata as md

        pgvector_py = md.version("pgvector")
    except Exception:
        pgvector_py = "?"

    return {
        "python": sys.version.split()[0],
        "platform": platform.platform(),
        "machine": platform.machine(),
        "processor": platform.processor() or platform.machine(),
        "cpu_count": os.cpu_count(),
        "torch": torch.__version__,
        "torch_threads": torch.get_num_threads(),
        "transformers": transformers.__version__,
        "flask": md.version("flask") if "md" in dir() else flask.__version__,
        "sqlalchemy": sqlalchemy.__version__,
        "pgvector_python": pgvector_py,
    }


# --------------------------------------------------------------- in-proc ----


class InProcessDriver:
    """Drives the app through Flask's test client (no sockets)."""

    label = "in-process (Flask test client, excludes HTTP/WSGI overhead)"

    def __init__(self, user_id: str):
        from app import create_app

        self.app = create_app()
        self.ctx = self.app.app_context()
        self.ctx.push()
        self.client = self.app.test_client()
        self.headers = {"X-User-Id": user_id}
        self.services = self.app.extensions["fitr"]

    def post(self, path, **kw):
        return self.client.post(path, headers=self.headers, **kw)

    def get(self, path, **kw):
        return self.client.get(path, headers=self.headers, **kw)

    def close(self):
        self.ctx.pop()


class HttpDriver:
    """Drives a real server over loopback HTTP."""

    def __init__(self, base_url: str, user_id: str):
        import requests

        self.base = base_url.rstrip("/")
        self.session = requests.Session()
        self.headers = {"X-User-Id": user_id}
        self.label = f"HTTP against {self.base} (includes socket + WSGI overhead)"
        self.services = None

    class _Resp:
        def __init__(self, r):
            self._r = r
            self.status_code = r.status_code

        def get_json(self):
            return self._r.json()

    def post(self, path, json=None, data=None, content_type=None, files=None):
        """JSON/form POST. Image uploads go through ``post_image`` instead."""
        return self._Resp(
            self.session.post(
                self.base + path, json=json, data=data, files=files, headers=self.headers
            )
        )

    def post_image(self, path, image: bytes, fields: dict | None = None):
        return self._Resp(
            self.session.post(
                self.base + path,
                files={"image": ("item.jpg", image, "image/jpeg")},
                data=fields or {},
                headers=self.headers,
            )
        )

    def get(self, path, **kw):
        return self._Resp(self.session.get(self.base + path, headers=self.headers))

    def close(self):
        self.session.close()


def post_image(driver, path: str, image: bytes, fields: dict | None = None):
    if isinstance(driver, HttpDriver):
        return driver.post_image(path, image, fields)
    payload = {"image": (io.BytesIO(image), "item.jpg")}
    payload.update(fields or {})
    return driver.post(path, data=payload, content_type="multipart/form-data")


# ------------------------------------------------------------------- run ----


def run(args) -> dict:
    run_salt = uuid.uuid4().hex[:8]
    user_id = f"{BENCH_USER_PREFIX}{run_salt}"
    driver = HttpDriver(args.http, user_id) if args.http else InProcessDriver(user_id)
    samples: list[Sample] = []
    meta: dict = {"mode": driver.label, "user_id": user_id, "run_salt": run_salt}

    print(f"mode : {driver.label}")
    print(f"user : {user_id}")

    # -- model load ------------------------------------------------------
    if driver.services is not None:
        encoder = driver.services.encoder
        t0 = time.perf_counter()
        encoder.load()
        meta["clip_model"] = encoder.model_id
        meta["clip_load_ms"] = round((time.perf_counter() - t0) * 1000.0, 2)
        meta["embedding_dim"] = encoder.dim
        print(f"clip : {encoder.model_id} loaded in {meta['clip_load_ms']:.0f} ms")

    health = driver.get("/api/v1/health").get_json()
    meta["pgvector"] = health["database"]["pgvector"]
    meta["gemini_configured"] = health["gemini"]["configured"]
    meta["weather_configured"] = health["weather"]["configured"]

    # -- seed wardrobe ---------------------------------------------------
    print(f"seed : creating {args.items} wardrobe items (cold CLIP on each) ...")
    cold_create = Sample(
        "wardrobe item create, cold (CLIP inference + insert)",
        "ms",
        note="first time these bytes are seen; includes the CLIP forward pass",
    )
    images: list[bytes] = []
    seed_started = time.perf_counter()
    for i in range(args.items):
        image = make_image(i, run_salt)
        images.append(image)
        fields = {
            "name": f"item {i}",
            "type": TYPES[i % len(TYPES)],
            "color": f"color{i % 12}",
            "style_tags": "casual",
            "weather_tags": "Cool",
        }
        t0 = time.perf_counter()
        resp = post_image(driver, "/api/v1/wardrobe/items", image, fields)
        elapsed = (time.perf_counter() - t0) * 1000.0
        assert resp.status_code == 201, resp.get_json()
        cold_create.add(elapsed)
        if (i + 1) % 100 == 0:
            print(f"       {i + 1}/{args.items} ({time.perf_counter() - seed_started:.0f}s)")
    samples.append(cold_create)
    meta["seed_seconds"] = round(time.perf_counter() - seed_started, 1)

    reps = min(args.reps, args.items)

    # -- embeddings endpoint: cold / L1 / L2 -----------------------------
    cold_embed = Sample(
        "POST /embeddings, cache MISS (runs CLIP)", "ms", note="cold path"
    )
    for i in range(reps):
        image = make_image(100_000 + i, run_salt)  # never seen before, thanks to the salt
        t0 = time.perf_counter()
        body = post_image(driver, "/api/v1/embeddings", image).get_json()
        cold_embed.add((time.perf_counter() - t0) * 1000.0)
        assert body["cache_tier"] == "miss", body
    samples.append(cold_embed)

    # With more than one worker process, a "warm" request round-robins to a
    # worker that may not hold the image in its own L1 and will fall through to
    # the shared L2 instead. That is correct behaviour and precisely why L2
    # exists, so record the observed tiers rather than asserting a single one.
    warm_tiers: dict[str, int] = {}
    warm_cached = Sample(
        "POST /embeddings, cache HIT", "ms", note="warm; tier distribution below"
    )
    for i in range(reps):
        image = images[i]
        post_image(driver, "/api/v1/embeddings", image)  # ensure resident
        t0 = time.perf_counter()
        body = post_image(driver, "/api/v1/embeddings", image).get_json()
        warm_cached.add((time.perf_counter() - t0) * 1000.0)
        tier = body["cache_tier"]
        warm_tiers[tier] = warm_tiers.get(tier, 0) + 1
        assert tier in ("l1", "l2"), body
    warm_cached.note = f"warm; tiers served: {warm_tiers}"
    samples.append(warm_cached)
    meta["warm_tier_distribution"] = warm_tiers

    if driver.services is not None:
        warm_l2 = Sample(
            "POST /embeddings, L2 hit (Postgres cache)",
            "ms",
            note="warm after a worker restart; L1 dropped before each call",
        )
        for i in range(reps):
            driver.services.cache.clear_l1()
            t0 = time.perf_counter()
            body = post_image(driver, "/api/v1/embeddings", images[i]).get_json()
            warm_l2.add((time.perf_counter() - t0) * 1000.0)
            assert body["cache_tier"] == "l2", body
        samples.append(warm_l2)

    # -- classify: the full image request, cold vs warm ------------------
    cold_classify = Sample("POST /vision/classify, cache MISS", "ms", note="cold path")
    for i in range(reps):
        image = make_image(200_000 + i, run_salt)
        t0 = time.perf_counter()
        body = post_image(driver, "/api/v1/vision/classify", image).get_json()
        cold_classify.add((time.perf_counter() - t0) * 1000.0)
        assert body["cache_tier"] == "miss", body
    samples.append(cold_classify)

    warm_classify = Sample(
        "POST /vision/classify, cache HIT",
        "ms",
        note="same image again; this is the 'repeat request' path",
    )
    for i in range(reps):
        t0 = time.perf_counter()
        post_image(driver, "/api/v1/vision/classify", images[i])
        warm_classify.add((time.perf_counter() - t0) * 1000.0)
    samples.append(warm_classify)

    # -- similarity search ------------------------------------------------
    knn = Sample(
        f"POST /wardrobe/search, pgvector k-NN over {args.items} items", "ms"
    )
    knn_retrieval = Sample("  of which: SQL retrieval only", "ms")
    for i in range(reps):
        t0 = time.perf_counter()
        body = driver.post(
            "/api/v1/wardrobe/search",
            json={"query": f"a {VIBES[i % len(VIBES)]} outfit for cold weather", "k": 12},
        ).get_json()
        knn.add((time.perf_counter() - t0) * 1000.0)
        knn_retrieval.add(body["timings_ms"]["retrieval"])
    samples.append(knn)
    samples.append(knn_retrieval)

    # -- recommendations --------------------------------------------------
    if meta["gemini_configured"]:
        rec_note = "INCLUDES the Gemini round trip"
    else:
        rec_note = (
            "EXCLUDES the Gemini call: no API key was configured, so the "
            "heuristic ranker produced the options"
        )
    cold_rec = Sample(
        "POST /recommendations, first time for this situation", "ms", note=rec_note
    )
    for i in range(reps):
        weather = {
            "temperature": 30.0 + i,
            "condition": CONDITIONS[i % len(CONDITIONS)],
            "units": "imperial",
            "location": "Bench",
            "humidity": 50,
            "wind_speed": 5.0,
        }
        t0 = time.perf_counter()
        resp = driver.post(
            "/api/v1/recommendations",
            json={"vibe": VIBES[i % len(VIBES)], "weather": weather, "candidate_k": 12},
        )
        cold_rec.add((time.perf_counter() - t0) * 1000.0)
        assert resp.status_code == 201, resp.get_json()
    samples.append(cold_rec)

    warm_rec = Sample(
        "POST /recommendations, repeat of an identical situation",
        "ms",
        note=rec_note + "; query-text embedding served from cache",
    )
    weather = {
        "temperature": 42.0,
        "condition": "Rainy",
        "units": "imperial",
        "location": "Bench",
        "humidity": 80,
        "wind_speed": 8.0,
    }
    driver.post(
        "/api/v1/recommendations",
        json={"vibe": "casual", "weather": weather, "candidate_k": 12},
    )
    for _ in range(reps):
        t0 = time.perf_counter()
        driver.post(
            "/api/v1/recommendations",
            json={"vibe": "casual", "weather": weather, "candidate_k": 12},
        )
        warm_rec.add((time.perf_counter() - t0) * 1000.0)
    samples.append(warm_rec)

    server_side = driver.get("/api/v1/metrics/latency?generator=heuristic").get_json()
    cache_stats = driver.get("/api/v1/metrics/cache").get_json()

    result = {
        "environment": environment(),
        "meta": meta,
        "parameters": {"items": args.items, "reps": reps},
        "measurements": [s.summary() for s in samples],
        "server_side_recommendation_latency": server_side,
        "cache": cache_stats,
    }

    if not args.keep:
        cleanup(driver, user_id)
    driver.close()
    return result


def cleanup(driver, user_id: str) -> None:
    if isinstance(driver, HttpDriver):
        print("note : --http mode leaves benchmark rows in the database")
        return
    from sqlalchemy import delete

    from app.extensions import db
    from app.models import ClothingItem, Recommendation, RecommendationFeedback

    db.session.execute(
        delete(RecommendationFeedback).where(RecommendationFeedback.user_id == user_id)
    )
    db.session.execute(delete(Recommendation).where(Recommendation.user_id == user_id))
    db.session.execute(delete(ClothingItem).where(ClothingItem.user_id == user_id))
    db.session.commit()


def render(result: dict) -> str:
    env = result["environment"]
    meta = result["meta"]
    lines = [
        "",
        "=" * 78,
        "fitr backend benchmark",
        "=" * 78,
        f"mode        : {meta['mode']}",
        f"host        : {env['platform']} / {env['machine']} / {env['cpu_count']} CPUs",
        f"python      : {env['python']}  torch {env['torch']} "
        f"({env['torch_threads']} threads)  transformers {env['transformers']}",
        f"pgvector    : {meta.get('pgvector')}",
        f"clip        : {meta.get('clip_model')} "
        f"dim={meta.get('embedding_dim')} load={meta.get('clip_load_ms')} ms",
        f"wardrobe    : {result['parameters']['items']} items "
        f"(seeded in {meta.get('seed_seconds')}s)",
        f"gemini key  : {'present' if meta.get('gemini_configured') else 'ABSENT'}",
        f"weather key : {'present' if meta.get('weather_configured') else 'ABSENT'}",
        "",
        f"{'measurement':<58} {'n':>4} {'p50':>8} {'p95':>8} {'max':>8}",
        "-" * 90,
    ]
    for m in result["measurements"]:
        if not m.get("n"):
            continue
        lines.append(
            f"{m['name']:<58} {m['n']:>4} {m['p50']:>8.2f} {m['p95']:>8.2f} {m['max']:>8.2f}"
        )
    lines.append("")
    for m in result["measurements"]:
        if m.get("note"):
            lines.append(f"  * {m['name']}: {m['note']}")
    lines.append("")
    if not meta.get("gemini_configured"):
        lines += [
            "IMPORTANT: no Gemini API key was present. Every /recommendations number",
            "above therefore EXCLUDES the LLM round trip and reflects the heuristic",
            "ranker. Set GEMINI_API_KEY and rerun for an end-to-end figure.",
            "",
        ]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--items", type=int, default=200, help="wardrobe size to seed")
    parser.add_argument("--reps", type=int, default=30, help="samples per measurement")
    parser.add_argument("--http", default="", help="benchmark a running server at this base URL")
    parser.add_argument("--json", default="", help="write full results to this path")
    parser.add_argument("--keep", action="store_true", help="do not delete benchmark rows")
    args = parser.parse_args()

    result = run(args)
    print(render(result))
    if args.json:
        with open(args.json, "w") as fh:
            json.dump(result, fh, indent=2)
        print(f"wrote {args.json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
