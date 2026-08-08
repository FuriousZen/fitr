# fitr backend

Flask service that does the parts of fitr that don't belong on a phone: CLIP
image embeddings, vector search over a wardrobe, weather lookup, and outfit
generation via Gemini.

```
                       ┌────────────────────────────────────────────┐
  iOS app ──HTTP──▶    │  Flask                                     │
                       │    │                                       │
                       │    ├─▶ OpenWeatherMap  (conditions)        │
                       │    ├─▶ CLIP ViT-B/32   (image + text)      │
                       │    ├─▶ Postgres+pgvector (k-NN + cache)    │
                       │    └─▶ Gemini          (ranks shortlist)   │
                       └────────────────────────────────────────────┘
```

The recommendation path is:

1. Resolve weather (coordinates or city, 1-hour TTL cache).
2. Build a sentence describing the situation — *"a photo of a casual outfit to
   wear in cold rainy weather"* — and embed it with CLIP's **text** tower.
3. Cosine k-NN in Postgres against the CLIP **image** embeddings of that user's
   clean garments, using an HNSW index.
4. Hand the shortlist (not the whole wardrobe) to Gemini, which returns up to
   three ranked outfits as structured JSON.

CLIP is load-bearing rather than decorative: it is what bounds the prompt, so
the Gemini call costs the same whether the user owns 20 garments or 2,000.

---

## Requirements

| Component | Version used and tested |
|---|---|
| Python | 3.12.13 |
| PostgreSQL | 15.18 |
| pgvector | 0.8.6 (built from source) |
| torch | 2.13.0+cpu |
| transformers | 5.14.1 |
| Flask | 3.1.3 |
| SQLAlchemy | 2.0.51 |
| psycopg | 3.3.4 |
| google-genai | 2.17.0 |

CPU-only. No GPU is used or required.

---

## Setup

### 1. PostgreSQL with pgvector

pgvector is **not** in Debian 12's apt repositories (`apt-cache policy
postgresql-15-pgvector` returns nothing), so it is built from source here. On a
distro that carries it, `sudo apt install postgresql-$(pg_config --version |
grep -oE '[0-9]+' | head -1)-pgvector` is the shorter path.

```bash
sudo apt-get install -y postgresql postgresql-contrib
sudo apt-get install -y build-essential postgresql-server-dev-15 git
sudo pg_ctlcluster 15 main start

git clone --branch v0.8.6 https://github.com/pgvector/pgvector.git /tmp/pgvector
cd /tmp/pgvector && make && sudo make install
```

> pgvector compiles with `-march=native`. If you build in one container and run
> in another with a different CPU, rebuild with `make OPTFLAGS=""` or you will
> get `Illegal instruction`.

Create the role, the databases, and the extension. `CREATE EXTENSION vector`
requires **superuser** — pgvector is not a trusted extension (there is no
`trusted = true` in `vector.control`), so it cannot be created by the
application role:

```bash
sudo -u postgres psql -c "CREATE ROLE fitr LOGIN PASSWORD 'fitr';"
sudo -u postgres createdb -O fitr fitr
sudo -u postgres createdb -O fitr fitr_test
sudo -u postgres psql -d fitr      -c 'CREATE EXTENSION IF NOT EXISTS vector;'
sudo -u postgres psql -d fitr_test -c 'CREATE EXTENSION IF NOT EXISTS vector;'
```

### 2. Python environment

torch must come from the CPU wheel index — the default PyPI wheel drags in
several GB of CUDA packages that are useless here.

```bash
python3 -m venv .venv-backend
.venv-backend/bin/pip install --upgrade pip
.venv-backend/bin/pip install torch torchvision \
    --index-url https://download.pytorch.org/whl/cpu
.venv-backend/bin/pip install -r backend/requirements.txt
```

### 3. Configuration

```bash
cp backend/.env.example backend/.env
$EDITOR backend/.env
```

`backend/.env` is gitignored. Every setting is read from the environment; no
key has a default and nothing is hardcoded. Without `GEMINI_API_KEY` or
`OPENWEATHERMAP_API_KEY` the service still starts and degrades in a documented
way (see *Degraded modes*).

### 4. Create the schema

```bash
cd backend && FLASK_APP=wsgi:app ../.venv-backend/bin/flask init-db
```

### 5. Run

```bash
cd backend
../.venv-backend/bin/flask --app wsgi:app run --port 8000        # development
../.venv-backend/bin/gunicorn -w 2 -t 120 -b 0.0.0.0:8000 wsgi:app  # production-ish
```

Each gunicorn worker loads its own ~600 MB copy of the CLIP weights and has its
own L1 cache. The shared Postgres L2 cache is what stops N workers from
recomputing the same embedding N times.

---

## Authentication

`FITR_AUTH_MODE` selects how the caller is identified:

| Mode | Mechanism | Use |
|---|---|---|
| `header` (default) | `X-User-Id: <uid>` | Development and tests only — anyone can claim any uid. |
| `firebase` | `Authorization: Bearer <Firebase ID token>` | Production. Verified with `google.oauth2.id_token.verify_firebase_token` against Google's public certs and `FITR_FIREBASE_PROJECT_ID`. |

> The `firebase` path has **never been exercised against a real Firebase
> project** — there are no credentials in the development environment. It is
> written from the documented API and is covered only by a test asserting that
> an unverifiable token is rejected. Verify it yourself before deploying.

---

## API

Base path `/api/v1`. All responses are JSON. Errors are uniformly
`{"error": {"code": "...", "message": "..."}}` with status 400/401/404/413/422/500/503.

### Health

| Method | Path | Notes |
|---|---|---|
| `GET` | `/healthz` | Liveness. No auth. Touches the database only. |
| `GET` | `/api/v1/health` | Readiness: CLIP state, cache stats, which third-party keys are configured. |

### Embeddings and recognition

| Method | Path | Notes |
|---|---|---|
| `POST` | `/api/v1/embeddings` | Embed an image. Returns `cache_tier` (`miss`/`l2`/`l1`), `content_hash`, `elapsed_ms`. `include_vector=true` also returns the 512 floats. |
| `POST` | `/api/v1/vision/classify` | CLIP zero-shot classification into the app's taxonomy. |

Both accept either `multipart/form-data` with an `image` part, or JSON with
`image_base64` (a `data:` URL prefix is stripped if present).

```bash
curl -s -X POST localhost:8000/api/v1/embeddings \
  -H 'X-User-Id: demo' -F image=@shirt.jpg
```
```json
{"content_hash":"a7bd18…","model_id":"openai/clip-vit-base-patch32",
 "dim":512,"cache_tier":"miss","elapsed_ms":266.69,"compute_ms":266.69}
```

Send it again and `cache_tier` becomes `l1` with `elapsed_ms` around 0.3.

`/vision/classify` returns the best label per head plus the top-3 scores:

```json
{"type":"Jeans","type_confidence":0.1665,"color":"blue","color_confidence":0.31,
 "style_tags":["casual","everyday"],"weather_tags":["Cool","Cold"],
 "scores":{"type":[{"label":"Jeans","score":0.1665}, …]},
 "cache_tier":"l1","content_hash":"…"}
```

> These confidences are a softmax over CLIP cosine similarities. Zero-shot
> accuracy has **not** been evaluated on any clothing benchmark; do not read
> them as validated classifier probabilities.

### Wardrobe

| Method | Path | Notes |
|---|---|---|
| `POST` | `/api/v1/wardrobe/items` | Create. With an image, computes/reuses its embedding. `id` may be supplied to match a Firestore document id. |
| `GET` | `/api/v1/wardrobe/items` | List. Filters: `dirty`, `type`, `limit`, `offset`. |
| `GET` | `/api/v1/wardrobe/items/<id>` | Fetch one. `include_embedding=true` to include the vector. |
| `PATCH` | `/api/v1/wardrobe/items/<id>` | Partial update; unspecified fields are untouched. |
| `DELETE` | `/api/v1/wardrobe/items/<id>` | Delete. The shared cache entry is deliberately retained. |
| `POST` | `/api/v1/wardrobe/wash` | Bulk-clear `dirty` for `item_ids`. |
| `GET` | `/api/v1/wardrobe/items/<id>/similar` | k-NN against the caller's other items. `k` (default 5). |
| `POST` | `/api/v1/wardrobe/search` | Natural-language search: `{"query": "...", "k": 10, "include_dirty": true}`. |
| `POST` | `/api/v1/wardrobe/reembed` | Lists items that have no embedding. |

Items are scoped to the caller. Another user's item id returns 404, not 403, so
the API cannot be used to probe for existence.

### Weather

| Method | Path | Notes |
|---|---|---|
| `GET` | `/api/v1/weather?lat=&lon=` or `?q=` | OpenWeatherMap passthrough, normalised into the Swift `Weather` shape, cached for `FITR_WEATHER_TTL_SECONDS`. |

Coordinates are rounded to 2 dp (~1.1 km) for the cache key, so GPS jitter does
not cost an API call.

### Recommendations

| Method | Path | Notes |
|---|---|---|
| `POST` | `/api/v1/recommendations` | Generate ranked outfits. |
| `GET` | `/api/v1/recommendations/<id>` | Retrieve a stored one. |
| `POST` | `/api/v1/recommendations/<id>/feedback` | Record whether the user wore an option. |

```bash
curl -s -X POST localhost:8000/api/v1/recommendations \
  -H 'X-User-Id: demo' -H 'Content-Type: application/json' \
  -d '{"vibe":"casual","lat":38.03,"lon":-78.48,"num_options":3}'
```

Supply either `lat`+`lon`, or `q`, or a complete `weather` object (which skips
the OpenWeatherMap call entirely — useful when the client already has it, and
what the tests use).

The response carries `generator`, which says what actually produced the
ranking: `gemini`, `heuristic`, `gemini_empty_fallback`, or `none` (empty
wardrobe). It also carries a `timings_ms` breakdown across weather / clip /
retrieval / generation.

Feedback: `{"accepted": true, "accepted_rank": 1}` where `accepted_rank` is the
1-based position of the option the user chose, or `{"accepted": false}`.

### Metrics

| Method | Path | Notes |
|---|---|---|
| `GET` | `/api/v1/metrics/acceptance?top_k=3` | Top-k acceptance computed from submitted feedback. |
| `GET` | `/api/v1/metrics/latency?generator=` | Nearest-rank percentiles over stored recommendations. |
| `GET` | `/api/v1/metrics/cache` | L1 and L2 cache statistics. |

**`top_k_acceptance` is `null` until real users submit feedback, and nothing in
this repository writes synthetic feedback.** The endpoint is instrumentation
for measuring an acceptance rate, not a source of one.

---

## The embedding cache

```
key = sha256(raw image bytes) + model_id

  L1   in-process LRU (FITR_EMBED_CACHE_SIZE, default 512)   ~0.3 ms
  L2   Postgres image_embeddings                             ~1.5 ms
  --   CLIP forward pass on CPU                              ~25-40 ms
```

Content addressing means the cache hits across re-uploads and across users
uploading the same file. Including `model_id` in the key means changing
`FITR_CLIP_MODEL` cannot serve a vector produced by a different model.

`clothing_items.embedding` holds a denormalised copy of the vector so the HNSW
index can serve per-user k-NN without a join. Deleting an item does not delete
the shared cache row.

There is a third cache: a bounded LRU over **text** embeddings, covering both
the fixed label vocabulary and recommendation query strings. Query text is
drawn from vibe × temperature-band × condition, a small enough space that
repeat requests essentially always hit.

---

## Is the HNSW index actually used?

Worth checking rather than assuming — a small table, or a filter the planner
dislikes, will quietly produce a sequential scan. With 5,000 rows:

```sql
EXPLAIN (ANALYZE, COSTS OFF)
SELECT id FROM clothing_items
WHERE user_id = 'demo' AND dirty = false
ORDER BY embedding <=> '[...]'::vector
LIMIT 12;
```
```
 Limit (actual time=0.231..0.255 rows=12 loops=1)
   ->  Index Scan using ix_clothing_items_embedding_hnsw on clothing_items
         Order By: (embedding <=> $0)
         Filter: ((NOT dirty) AND ((user_id)::text = 'demo'::text))
 Execution Time: 0.279 ms
```

The index is used, and the `user_id`/`dirty` predicate is applied as a filter
on top of it.

> **Caveat for multi-tenant vector search.** Because that predicate is a
> *post*-filter on the index scan, pgvector walks the graph in global distance
> order and discards rows belonging to other users. When one user's garments
> are a small fraction of the table, it may have to traverse far more of the
> graph to find `k` survivors, and can return fewer than `k` if `hnsw.ef_search`
> is exhausted first. It is correct here at this scale, but a deployment with
> many users and large wardrobes should raise `hnsw.ef_search`, or partition by
> user, and re-check recall. No recall measurement is claimed.

---

## Degraded modes

Missing credentials degrade the service; they never crash it.

| Missing | Effect |
|---|---|
| `GEMINI_API_KEY` | `/recommendations` still returns ranked outfits, built by the CLIP-ordered heuristic ranker. `generator` reports `heuristic`. |
| `OPENWEATHERMAP_API_KEY` | `/weather` returns 503. `/recommendations` still works if the client passes a `weather` object. |
| CLIP weights unavailable | Embedding, classification and search return 503 with the load error. |

A Gemini failure mid-request falls back to the heuristic ranker rather than
failing the request, so a third-party outage degrades quality, not uptime.

---

## Notes on the libraries

These were verified against current documentation and then re-verified by
introspecting the installed packages. Several contradict what the code would
look like if written from memory.

**transformers 5.x changed the CLIP feature API.** `get_image_features()` now
returns `BaseModelOutputWithPooling`, not a tensor. The 512-d projected
embedding is `.pooler_output`; `.last_hidden_state` is the 768-d
pre-projection output. `app/services/clip.py` handles both the 4.x and 5.x
shapes, and `tests/test_clip_real.py` pins the behaviour.

**CLIP features are not normalised.** `CLIPModel.forward` normalises
internally before computing logits, so the feature helpers return unnormalised
vectors. Everything is L2-normalised at write time here, which makes cosine
distance and `1 - dot` equivalent.

**Model choice: HuggingFace `transformers`, not `open_clip_torch`.** Both ship
ViT-B/32 at 512 dims and ~605 MB, so there is no quality or size difference.
open_clip has the more stable API (and a built-in `normalize=True`), which is a
genuine argument in its favour given the churn above; transformers wins here
only because torchvision is already required by the v5 image pipeline, so
open_clip's extra chain (notably `timm`) buys nothing. The version is pinned
`>=5,<6` because an unpinned upgrade across the 4→5 boundary silently changes
the return type.

**`google-generativeai` is dead.** Deprecated, end-of-life 2025-11-30. This
uses the unified `google-genai` SDK (`from google import genai`).

**The model ids in the Swift app are retired.** `gemini-2.0-flash` was shut
down 2026-06-01 and the `gemini-1.5-*` family earlier, so both
`ClothingClassifierService.swift` and `OutfitService.swift` currently name
models that no longer exist. The backend defaults to `gemini-3.6-flash`.

**`types.HttpOptions(timeout=…)` is milliseconds**, not seconds.

**pgvector needs superuser for `CREATE EXTENSION`** — it is not a trusted
extension.

---

## Tests

```bash
cd backend
../.venv-backend/bin/python -m pytest            # 157 tests
../.venv-backend/bin/python -m pytest --run-clip # + 9 against real CLIP weights
```

Tests run against a **real** PostgreSQL + pgvector (`fitr_test`); the vector
behaviour is the point, so the database is not stubbed. CLIP is faked by
default (a deterministic hash-derived encoder with the same interface) because
loading real weights costs ~4 s and 600 MB; `--run-clip` swaps in the genuine
model and asserts embedding shape, unit norm, determinism, the
`.pooler_output` unpacking, and that a red swatch really does score highest
against "a red piece of clothing".

Gemini and OpenWeatherMap are never called. There are no API keys in this
environment and none were invented: Gemini is driven through a fake client
matching the introspected `google-genai` signature, and OpenWeatherMap through
`responses` with payloads shaped from its published schema.

---

## Benchmarking

```bash
cd backend
../.venv-backend/bin/python scripts/benchmark.py --items 1500 --reps 50
../.venv-backend/bin/python scripts/benchmark.py --http http://127.0.0.1:8000
```

The script prints the host, CPU count and library versions alongside the
numbers, seeds a wardrobe, and measures cold vs warm paths at each tier. A
per-run salt makes the "cold" images genuinely novel — without it the
persistent L2 cache would serve them and the script would measure the warm path
while labelling it cold.

Measured results and how they compare to the project's headline claims are in
the root [`README.md`](../README.md#measured-performance).
