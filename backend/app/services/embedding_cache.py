"""Two-tier, content-addressed embedding cache.

    L1  in-process LRU        ~microseconds, per-worker, lost on restart
    L2  Postgres              ~1 ms, shared by all workers, survives restarts
    --  CLIP forward pass     hundreds of ms on CPU

Keying is ``sha256(raw image bytes)`` plus the model id. Content addressing
means the cache hits across users and across re-uploads of the same file, and
that changing ``FITR_CLIP_MODEL`` cannot silently serve vectors from the wrong
model.
"""

from __future__ import annotations

import hashlib
import threading
import time
from collections import OrderedDict
from dataclasses import dataclass

import numpy as np
from sqlalchemy import select, update

from ..extensions import db
from ..models import ImageEmbedding
from .clip import ClipEncoder

L1 = "l1"
L2 = "l2"
MISS = "miss"


def content_hash(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


@dataclass(frozen=True)
class CachedEmbedding:
    vector: np.ndarray
    content_hash: str
    tier: str
    elapsed_ms: float
    compute_ms: float | None


class EmbeddingCache:
    def __init__(self, encoder: ClipEncoder, max_entries: int = 512) -> None:
        self.encoder = encoder
        self.max_entries = max(1, int(max_entries))
        self._l1: OrderedDict[str, np.ndarray] = OrderedDict()
        self._lock = threading.Lock()
        self.stats = {L1: 0, L2: 0, MISS: 0}

    # -- L1 ----------------------------------------------------------------

    def _l1_key(self, digest: str) -> str:
        return f"{self.encoder.model_id}:{digest}"

    def _l1_get(self, digest: str) -> np.ndarray | None:
        key = self._l1_key(digest)
        with self._lock:
            vec = self._l1.get(key)
            if vec is not None:
                self._l1.move_to_end(key)
            return vec

    def _l1_put(self, digest: str, vec: np.ndarray) -> None:
        key = self._l1_key(digest)
        with self._lock:
            self._l1[key] = vec
            self._l1.move_to_end(key)
            while len(self._l1) > self.max_entries:
                self._l1.popitem(last=False)

    # -- public ------------------------------------------------------------

    def get_or_compute(self, data: bytes) -> CachedEmbedding:
        started = time.perf_counter()
        digest = content_hash(data)

        vec = self._l1_get(digest)
        if vec is not None:
            self.stats[L1] += 1
            return CachedEmbedding(
                vector=vec,
                content_hash=digest,
                tier=L1,
                elapsed_ms=(time.perf_counter() - started) * 1000.0,
                compute_ms=None,
            )

        row = db.session.get(ImageEmbedding, (digest, self.encoder.model_id))
        if row is not None:
            vec = np.asarray(row.embedding, dtype=np.float32)
            self._l1_put(digest, vec)
            self.stats[L2] += 1
            # Bump the counter without loading/flushing the vector back.
            db.session.execute(
                update(ImageEmbedding)
                .where(
                    ImageEmbedding.content_hash == digest,
                    ImageEmbedding.model_id == self.encoder.model_id,
                )
                .values(hit_count=ImageEmbedding.hit_count + 1)
            )
            db.session.commit()
            return CachedEmbedding(
                vector=vec,
                content_hash=digest,
                tier=L2,
                elapsed_ms=(time.perf_counter() - started) * 1000.0,
                compute_ms=row.compute_ms,
            )

        result = self.encoder.encode_image_bytes(data)
        vec = result.vector
        self._l1_put(digest, vec)
        self.stats[MISS] += 1

        db.session.merge(
            ImageEmbedding(
                content_hash=digest,
                model_id=self.encoder.model_id,
                dim=int(vec.shape[0]),
                embedding=vec.tolist(),
                compute_ms=result.elapsed_ms,
                hit_count=0,
            )
        )
        db.session.commit()

        return CachedEmbedding(
            vector=vec,
            content_hash=digest,
            tier=MISS,
            elapsed_ms=(time.perf_counter() - started) * 1000.0,
            compute_ms=result.elapsed_ms,
        )

    def peek_tier(self, data: bytes) -> str:
        """Which tier *would* serve these bytes, without mutating anything.

        Reads the L1 dict directly rather than through ``_l1_get`` so the
        lookup does not count as a use and reorder the LRU.
        """
        digest = content_hash(data)
        with self._lock:
            if self._l1_key(digest) in self._l1:
                return L1
        exists = db.session.execute(
            select(ImageEmbedding.content_hash).where(
                ImageEmbedding.content_hash == digest,
                ImageEmbedding.model_id == self.encoder.model_id,
            )
        ).first()
        return L2 if exists else MISS

    def clear_l1(self) -> None:
        with self._lock:
            self._l1.clear()

    def health(self) -> dict:
        total = sum(self.stats.values())
        served_from_cache = self.stats[L1] + self.stats[L2]
        return {
            "l1_entries": len(self._l1),
            "l1_capacity": self.max_entries,
            "hits_l1": self.stats[L1],
            "hits_l2": self.stats[L2],
            "misses": self.stats[MISS],
            "requests": total,
            "hit_rate": round(served_from_cache / total, 4) if total else None,
        }
