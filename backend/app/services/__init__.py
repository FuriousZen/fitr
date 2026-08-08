"""Service container.

One instance per Flask app, stashed on ``app.extensions``. Services are plain
objects with constructor-injected config, so tests can build them directly or
swap them out (``app.extensions["fitr"].gemini = FakeGemini()``) without
monkeypatching module globals.
"""

from __future__ import annotations

from dataclasses import dataclass

from flask import current_app

from .clip import ClipEncoder
from .embedding_cache import EmbeddingCache
from .gemini import GeminiService
from .recommender import Recommender
from .vision import ZeroShotClassifier
from .weather import WeatherService

__all__ = [
    "ServiceRegistry",
    "build_services",
    "services",
    "ClipEncoder",
    "EmbeddingCache",
    "GeminiService",
    "Recommender",
    "WeatherService",
    "ZeroShotClassifier",
]


@dataclass
class ServiceRegistry:
    encoder: ClipEncoder
    cache: EmbeddingCache
    weather: WeatherService
    gemini: GeminiService
    recommender: Recommender
    classifier: ZeroShotClassifier


def build_services(config) -> ServiceRegistry:
    encoder = ClipEncoder(
        model_id=config["CLIP_MODEL"],
        device=config["CLIP_DEVICE"],
        expected_dim=config["EMBED_DIM"],
        torch_threads=config["TORCH_THREADS"],
        local_files_only=config["CLIP_LOCAL_FILES_ONLY"],
    )
    cache = EmbeddingCache(encoder, max_entries=config["EMBED_CACHE_SIZE"])
    weather = WeatherService(
        api_key=config["OPENWEATHERMAP_API_KEY"],
        units=config["WEATHER_UNITS"],
        ttl_seconds=config["WEATHER_TTL_SECONDS"],
    )
    gemini = GeminiService(
        api_key=config["GEMINI_API_KEY"],
        model=config["GEMINI_MODEL"],
        temperature=config["GEMINI_TEMPERATURE"],
        timeout_s=config["GEMINI_TIMEOUT_S"],
    )
    recommender = Recommender(encoder, gemini, candidate_k=config["CANDIDATE_K"])
    classifier = ZeroShotClassifier(encoder)
    return ServiceRegistry(
        encoder=encoder,
        cache=cache,
        weather=weather,
        gemini=gemini,
        recommender=recommender,
        classifier=classifier,
    )


def services() -> ServiceRegistry:
    return current_app.extensions["fitr"]
