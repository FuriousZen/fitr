"""Embedding and zero-shot recognition endpoints."""

from __future__ import annotations

from flask import Blueprint

from ..auth import require_user
from ..errors import ServiceUnavailable
from ..services import services
from ..services.clip import ClipUnavailableError
from .helpers import form_or_json, get_bool, read_image_bytes

bp = Blueprint("vision", __name__, url_prefix="/api/v1")


@bp.post("/embeddings")
@require_user
def create_embedding():
    """Embed an image, going through the two-tier cache.

    The response's ``cache_tier`` is the honest source for cold-vs-warm latency
    measurements: ``miss`` ran CLIP, ``l2`` came from Postgres, ``l1`` came from
    this worker's memory.
    """
    data = form_or_json()
    image_bytes = read_image_bytes()
    svc = services()
    try:
        cached = svc.cache.get_or_compute(image_bytes)
    except ClipUnavailableError as exc:
        raise ServiceUnavailable(str(exc)) from exc

    payload = {
        "content_hash": cached.content_hash,
        "model_id": svc.encoder.model_id,
        "dim": int(cached.vector.shape[0]),
        "cache_tier": cached.tier,
        "elapsed_ms": round(cached.elapsed_ms, 2),
        "compute_ms": round(cached.compute_ms, 2) if cached.compute_ms is not None else None,
    }
    if get_bool(data, "include_vector", False):
        payload["embedding"] = [float(x) for x in cached.vector]
    return payload


@bp.post("/vision/classify")
@require_user
def classify():
    """CLIP zero-shot recognition against the app's clothing taxonomy."""
    image_bytes = read_image_bytes()
    svc = services()
    try:
        cached = svc.cache.get_or_compute(image_bytes)
        result = svc.classifier.classify(cached.vector)
    except ClipUnavailableError as exc:
        raise ServiceUnavailable(str(exc)) from exc

    result["content_hash"] = cached.content_hash
    result["cache_tier"] = cached.tier
    result["elapsed_ms"] = round(cached.elapsed_ms, 2)
    return result
