# fitr: your personal outfit assistant

fitr combines your wardrobe, the local weather and your mood into an outfit
recommendation.

fitr is a SwiftUI iOS app plus a Flask backend. The app handles accounts,
wardrobe management and the UI; the backend does CLIP image embeddings, vector
search, weather lookup and Gemini-based outfit generation.

## Screenshots

<img src="assets/login.png" alt="Login Screen" width="150"> <img src="assets/gallery.png" alt="Gallery View" width="150">

<img src="assets/vibe.png" alt="Mood Selection" width="150"> <img src="assets/outfit_details.png" alt="Outfit Details" width="150">

<img src="assets/wardrobe.png" alt="Wardrobe Management" width="150">

---

## Architecture

```
┌──────────────────────────┐        ┌─────────────────────────────────────┐
│ iOS app (SwiftUI)        │        │ Flask backend (Python 3.12, CPU)    │
│                          │        │                                     │
│  Firebase Auth ──────────┼───ID───▶  auth: verify Firebase ID token     │
│  Firestore (profiles,    │  token │                                     │
│    wardrobe metadata)    │        │  CLIP ViT-B/32                      │
│  Firebase Storage        │  HTTP  │    image tower → garment vectors    │
│    (wardrobe images)     ├───────▶│    text tower  → situation vector   │
│  Kingfisher (image cache)│        │                                     │
│  Core Location ──────────┤        │  PostgreSQL 15 + pgvector 0.8.6     │
│                          │        │    HNSW cosine k-NN                 │
│  BackendService.swift ───┼───────▶│    embedding cache (content-addr.)  │
└──────────────────────────┘        │                                     │
                                    │  OpenWeatherMap → conditions        │
                                    │  Gemini         → ranks shortlist   │
                                    └─────────────────────────────────────┘
```

### What the app sends where

Firestore is the wardrobe's source of truth: profiles, item metadata and the
Storage URLs of the photos live there, behind Firebase Authentication. The
backend keeps its own copy of each item so it can run CLIP over the photo and
search the vectors. Every backend call carries the user's Firebase ID token,
which the backend verifies before it touches that user's rows.

| Action in the app | Firestore / Storage | Backend (`BackendService.swift`) |
|---|---|---|
| Analyze a photo | | `POST /api/v1/vision/classify` (CLIP zero-shot) |
| Save an item | Upload photo, write item | `POST /api/v1/wardrobe/items` with the photo, so the item gets an embedding and joins the k-NN index |
| Mark dirty, wash, delete | Update item | Same change mirrored to the backend copy |
| Open the dashboard | Read wardrobe | `GET /api/v1/weather?lat=&lon=` from Core Location |
| Pick a vibe | | `POST /api/v1/recommendations` with the vibe and the weather |

### How a recommendation is produced

1. The app resolves the device's coordinates with Core Location and asks the
   backend for the weather there (1-hour TTL cache on the backend). If the
   user has declined location access, the app says so on the dashboard and
   uses a fixed city instead.
2. The backend describes the situation in words (*"a photo of a casual outfit
   to wear in cold rainy weather"*) and embeds that with CLIP's text tower.
3. Cosine k-NN in Postgres against the CLIP image embeddings of the user's
   clean garments, served by an HNSW index.
4. That shortlist, not the whole wardrobe, goes to Gemini, which returns up
   to three ranked outfits as structured JSON. The app shows the top one.

CLIP is what bounds the prompt, so the Gemini call costs the same whether the
wardrobe holds 20 garments or 2,000.

### Without a backend

`BackendService.isConfigured` is false when `FITR_BACKEND_URL` is unset. The
app then calls Gemini through `FirebaseVertexAI` for classification and
outfits, and OpenWeatherMap directly for weather, all from the device. That
path is the original HooHacks build and needs `OPENWEATHERMAP_API_KEY` in the
app's environment. It skips CLIP and the vector index entirely, and the
Gemini model ids live in Swift, so a retired model means a new app build. The
backend path keeps the model ids, the API keys and the SDK versions on the
server.

### Tech stack

| Layer | Technology |
|---|---|
| iOS | SwiftUI, Core Location, Kingfisher |
| Accounts & profiles | Firebase Authentication |
| Metadata & images | Cloud Firestore, Firebase Storage |
| Backend | Flask 3.1, SQLAlchemy 2.0, psycopg 3 |
| Image recognition | CLIP ViT-B/32 (`openai/clip-vit-base-patch32`) via HuggingFace transformers, CPU-only |
| Vector store | PostgreSQL 15 + pgvector 0.8.6 (HNSW, cosine) |
| Outfit generation | Gemini via the `google-genai` SDK |
| Weather | OpenWeatherMap Current Weather Data (2.5) |

Backend setup, the full REST reference and library notes are in
[`backend/README.md`](backend/README.md).

---

## iOS setup

1. Add your Firebase project's `GoogleService-Info.plist` to the `fitr`
   target. It is gitignored. Enable Email/Password sign-in, Firestore and
   Storage in the Firebase console.
2. Start the backend (see `backend/README.md`) with `FITR_AUTH_MODE=firebase`
   and `FITR_FIREBASE_PROJECT_ID` set to the same project.
3. Tell the app where the backend is. `AppConfig` reads each key from the
   process environment first and then from `Info.plist`:

   | Key | Meaning |
   |---|---|
   | `FITR_BACKEND_URL` | Base URL of the backend, e.g. `http://192.168.1.10:8000`. Required for the CLIP path. |
   | `FITR_BACKEND_TIMEOUT` | Seconds before a backend request is abandoned. Default 30. |
   | `OPENWEATHERMAP_API_KEY` | Only for the no-backend fallback. Leave unset when `FITR_BACKEND_URL` is set. |

   For local runs, set them under Product → Scheme → Edit Scheme → Run →
   Arguments → Environment Variables. For a build that carries the value,
   the project generates its `Info.plist` from build settings, so add
   `INFOPLIST_KEY_FITR_BACKEND_URL = https://fitr.example.com` to the target's
   build settings or to an `.xcconfig`. `AppConfig` ignores blank values and
   the literal `$(FITR_BACKEND_URL)`, so an unfilled setting behaves as
   unset rather than as a broken URL.
4. Allow cleartext HTTP if the backend runs on a LAN address during
   development. App Transport Security refuses `http://` by default; add an
   `NSExceptionDomains` entry for your development host, not a blanket
   `NSAllowsArbitraryLoads`.
5. Build and run. Location and camera usage descriptions are already in the
   target's build settings (`INFOPLIST_KEY_NSLocationWhenInUseUsageDescription`,
   `INFOPLIST_KEY_NSCameraUsageDescription`), so iOS will prompt for both on
   first use.

`fitr.xcodeproj` uses a file-system-synchronized group for `fitr/`, so any
Swift file added under that directory is part of the target without editing
the project file.

### Tests

`fitrTests` covers the mapping between the backend's JSON and the app's
models (`BackendClassification` → `ClothingClassificationResult`,
`BackendRecommendation` → `Outfit`, date parsing, OpenWeatherMap condition
groups). `fitrUITests` launches the app and asserts that either the login
form or the dashboard appears. Run both with ⌘U.

---

## Repository layout

```
fitr/                       SwiftUI app
  Services/
    BackendService.swift             client for the Flask backend
    ClothingClassifierService.swift  backend CLIP, or Gemini on device
    OutfitService.swift              backend recommendation, or Gemini on device
    WeatherService.swift             OpenWeatherMap by coordinates (device fallback)
    FirebaseService.swift            Firestore + Storage, mirrored to the backend
  Utils/
    AppConfig.swift                  env / Info.plist configuration
    Constants.swift                  colours, collection names, API key lookup
  Views/                             dashboard, wardrobe, laundry, outfit, profile
fitrTests/                  model and mapping tests
fitrUITests/                launch test
backend/                    Flask service, see backend/README.md
  app/services/               clip, embedding_cache, weather, gemini, recommender, vision
  scripts/benchmark.py        latency tool for the backend tiers
  tests/                      pytest suite against a real PostgreSQL + pgvector
```

---

## Secrets

No key is committed. On the app side, values come from the environment or
`Info.plist` at run time via `AppConfig`. Backend configuration lives in
`backend/.env` (gitignored) with `backend/.env.example` as the committed
template.

Anything in `Info.plist` ships inside the `.ipa` and is readable by anyone
who downloads it, which is why the app sends third-party calls through the
backend when it can: the OpenWeatherMap and Gemini keys then stay on the
server.

---

## Origin

Built in under a day at HooHacks as a SwiftUI app calling Gemini and
OpenWeatherMap directly. The Flask backend, CLIP embeddings, Postgres/pgvector
storage and the embedding cache were added afterwards, and the app now uses
them whenever a backend URL is configured.
