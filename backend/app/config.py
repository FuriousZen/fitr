"""Configuration, sourced entirely from the process environment.

No secret has a default. If a key is absent the corresponding service reports
itself as unconfigured and the API degrades in a documented way rather than
failing at import time. That is what lets the test suite run without any real
credentials.
"""

from __future__ import annotations

import os

DEFAULT_DATABASE_URL = "postgresql+psycopg://fitr:fitr@127.0.0.1:5432/fitr"


def _env_bool(name: str, default: bool = False) -> bool:
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _env_int(name: str, default: int) -> int:
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    try:
        return int(raw)
    except ValueError:
        return default


def _env_float(name: str, default: float) -> float:
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    try:
        return float(raw)
    except ValueError:
        return default


class Config:
    """Base config. Values are resolved at class-definition time."""

    SQLALCHEMY_DATABASE_URI = os.environ.get("FITR_DATABASE_URL", DEFAULT_DATABASE_URL)
    SQLALCHEMY_ENGINE_OPTIONS = {"pool_pre_ping": True}

    # --- CLIP -------------------------------------------------------------
    CLIP_MODEL = os.environ.get("FITR_CLIP_MODEL", "openai/clip-vit-base-patch32")
    CLIP_DEVICE = os.environ.get("FITR_CLIP_DEVICE", "cpu")
    #: Dimension of the vector columns. Must match the model's projection_dim;
    #: ClipEncoder validates this on load and raises if they disagree.
    EMBED_DIM = _env_int("FITR_EMBED_DIM", 512)
    TORCH_THREADS = _env_int("FITR_TORCH_THREADS", 0)
    CLIP_EAGER = _env_bool("FITR_CLIP_EAGER", False)
    #: Skip all HuggingFace Hub HTTP calls at load time. Requires the weights to
    #: already be in the HF cache (or HF_HOME to point at a baked-in copy).
    CLIP_LOCAL_FILES_ONLY = _env_bool("FITR_CLIP_LOCAL_FILES_ONLY", False)
    EMBED_CACHE_SIZE = _env_int("FITR_EMBED_CACHE_SIZE", 512)

    # --- Gemini -----------------------------------------------------------
    #: GOOGLE_API_KEY takes precedence in the SDK when both are set, so mirror
    #: that ordering here.
    GEMINI_API_KEY = os.environ.get("GOOGLE_API_KEY") or os.environ.get("GEMINI_API_KEY") or ""
    GEMINI_MODEL = os.environ.get("FITR_GEMINI_MODEL", "gemini-3.6-flash")
    GEMINI_TEMPERATURE = _env_float("FITR_GEMINI_TEMPERATURE", 0.7)
    GEMINI_TIMEOUT_S = _env_float("FITR_GEMINI_TIMEOUT_S", 30.0)

    # --- Weather ----------------------------------------------------------
    OPENWEATHERMAP_API_KEY = os.environ.get("OPENWEATHERMAP_API_KEY", "")
    WEATHER_TTL_SECONDS = _env_int("FITR_WEATHER_TTL_SECONDS", 3600)
    WEATHER_UNITS = os.environ.get("FITR_WEATHER_UNITS", "imperial")

    # --- Auth -------------------------------------------------------------
    AUTH_MODE = os.environ.get("FITR_AUTH_MODE", "header").strip().lower()
    FIREBASE_PROJECT_ID = os.environ.get("FITR_FIREBASE_PROJECT_ID", "")

    # --- Misc -------------------------------------------------------------
    MAX_IMAGE_BYTES = _env_int("FITR_MAX_IMAGE_BYTES", 10 * 1024 * 1024)
    CANDIDATE_K = _env_int("FITR_CANDIDATE_K", 12)
    CORS_ORIGINS = os.environ.get("FITR_CORS_ORIGINS", "*")

    JSON_SORT_KEYS = False


class TestConfig(Config):
    TESTING = True
    SQLALCHEMY_DATABASE_URI = os.environ.get(
        "FITR_TEST_DATABASE_URL",
        "postgresql+psycopg://fitr:fitr@127.0.0.1:5432/fitr_test",
    )
    CLIP_EAGER = False
    AUTH_MODE = "header"
