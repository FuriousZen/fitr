"""Outfit recommendation and its acceptance instrumentation."""

from __future__ import annotations

import time

from flask import Blueprint

from ..auth import current_user_id, require_user
from ..errors import NotFound, ServiceUnavailable, ValidationError
from ..extensions import db
from ..models import Recommendation, RecommendationFeedback
from ..services import services
from ..services.clip import ClipUnavailableError
from ..services.weather import WeatherUnavailableError
from .helpers import form_or_json, get_bool, get_float, get_int, get_str

bp = Blueprint("recommendations", __name__, url_prefix="/api/v1/recommendations")


#: The unit systems OpenWeatherMap accepts, and the only ones
#: ``temperature_band`` knows how to convert from.
_UNIT_SYSTEMS = ("standard", "metric", "imperial")


def _validated_weather(explicit: dict) -> dict:
    """Check a client-supplied weather object before the recommender sees it.

    ``build_query_text`` calls ``float()`` on the temperature and ``.lower()``
    on the condition. Anything that is not a number or not a string reaches
    those calls and surfaces as a 500, so the types are checked here and
    reported as a validation error instead.
    """
    cleaned = dict(explicit)

    try:
        cleaned["temperature"] = float(cleaned["temperature"])
    except (TypeError, ValueError):
        raise ValidationError("weather.temperature must be a number") from None

    condition = cleaned.get("condition") or "Cloudy"
    if not isinstance(condition, str):
        raise ValidationError("weather.condition must be a string")
    cleaned["condition"] = condition

    units = cleaned.get("units") or services().weather.units
    if units not in _UNIT_SYSTEMS:
        raise ValidationError(
            f"weather.units must be one of {', '.join(_UNIT_SYSTEMS)}"
        )
    cleaned["units"] = units

    cleaned.setdefault("humidity", 0)
    cleaned.setdefault("wind_speed", 0.0)
    cleaned.setdefault("location", "")
    return cleaned


def _resolve_weather(data: dict) -> tuple[dict, float]:
    """Weather from an explicit object, or fetched from coordinates/city."""
    svc = services()
    explicit = data.get("weather")
    if isinstance(explicit, dict) and "temperature" in explicit:
        return _validated_weather(explicit), 0.0

    lat = get_float(data, "lat")
    lon = get_float(data, "lon")
    q = get_str(data, "q")
    if not q and (lat is None or lon is None):
        raise ValidationError(
            "provide a weather object, or q, or both lat and lon"
        )

    started = time.perf_counter()
    try:
        result = svc.weather.fetch(lat=lat, lon=lon, q=q or None)
    except WeatherUnavailableError as exc:
        raise ServiceUnavailable(str(exc)) from exc
    return result.data, (time.perf_counter() - started) * 1000.0


def _expand_options(options: list[dict], items_by_id: dict[str, dict]) -> list[dict]:
    """Inline the full item payload into each option so the client does not
    have to cross-reference ``candidates`` itself."""
    return [
        {
            **opt,
            "items": [
                items_by_id[i] for i in opt.get("item_ids", []) if i in items_by_id
            ],
        }
        for opt in options
    ]


@bp.post("")
@bp.post("/")
@require_user
def create_recommendation():
    """Generate ranked outfits.

    Pipeline: resolve weather -> CLIP-embed a text description of the situation
    -> pgvector k-NN shortlist of the user's clean items -> Gemini ranks them
    (or the heuristic ranker does, if Gemini is unconfigured).
    """
    user_id = current_user_id()
    data = form_or_json()
    svc = services()

    vibe = get_str(data, "vibe", "everyday")
    num_options = get_int(data, "num_options", 3, minimum=1, maximum=5)
    candidate_k = get_int(data, "candidate_k", svc.recommender.candidate_k, minimum=1, maximum=100)
    include_dirty = get_bool(data, "include_dirty", False)

    total_started = time.perf_counter()
    weather, weather_ms = _resolve_weather(data)

    try:
        outcome = svc.recommender.recommend(
            user_id=user_id,
            vibe=vibe,
            weather=weather,
            num_options=num_options,
            candidate_k=candidate_k,
            include_dirty=include_dirty,
        )
    except ClipUnavailableError as exc:
        raise ServiceUnavailable(str(exc)) from exc
    total_ms = (time.perf_counter() - total_started) * 1000.0

    record = Recommendation(
        user_id=user_id,
        vibe=vibe,
        weather=weather,
        query_text=outcome.query_text,
        candidate_item_ids=[c["id"] for c in outcome.candidates],
        options=outcome.options,
        generator=outcome.generator,
        model=outcome.model,
        total_ms=total_ms,
        weather_ms=weather_ms,
        clip_ms=outcome.timings.get("clip", 0.0),
        retrieval_ms=outcome.timings.get("retrieval", 0.0),
        generation_ms=outcome.timings.get("generation", 0.0),
    )
    db.session.add(record)
    db.session.commit()

    # The candidate payloads are already fully materialised dicts from the
    # shortlist query, so expand from those rather than issuing one SELECT per
    # candidate.
    items_by_id = {c["id"]: c for c in outcome.candidates}

    payload = record.to_dict()
    payload["options"] = _expand_options(outcome.options, items_by_id)
    payload["candidates"] = outcome.candidates
    return payload, 201


@bp.get("/<rec_id>")
@require_user
def get_recommendation(rec_id: str):
    user_id = current_user_id()
    record = db.session.get(Recommendation, rec_id)
    if record is None or record.user_id != user_id:
        raise NotFound(f"recommendation {rec_id!r} not found")
    return record.to_dict()


@bp.post("/<rec_id>/feedback")
@require_user
def submit_feedback(rec_id: str):
    """Record whether the user actually wore one of the ranked options.

    ``accepted_rank`` is the 1-based position of the option they chose. This is
    the raw material for a top-k acceptance rate; see /api/v1/metrics/acceptance.
    Nothing else in this repo writes to this table.
    """
    user_id = current_user_id()
    record = db.session.get(Recommendation, rec_id)
    if record is None or record.user_id != user_id:
        raise NotFound(f"recommendation {rec_id!r} not found")

    data = form_or_json()
    if "accepted" not in data:
        raise ValidationError("accepted is required")
    accepted = get_bool(data, "accepted")

    accepted_rank = None
    if accepted:
        if "accepted_rank" not in data:
            raise ValidationError("accepted_rank is required when accepted is true")
        accepted_rank = get_int(data, "accepted_rank", 1, minimum=1, maximum=50)
        available = len(record.options or [])
        if accepted_rank > available:
            raise ValidationError(
                f"accepted_rank {accepted_rank} exceeds the {available} option(s) offered"
            )

    existing = db.session.get(RecommendationFeedback, rec_id)
    feedback = RecommendationFeedback(
        id=rec_id,  # one feedback row per recommendation
        recommendation_id=rec_id,
        user_id=user_id,
        accepted=accepted,
        accepted_rank=accepted_rank,
        note=get_str(data, "note") or None,
    )
    if existing is not None:
        db.session.delete(existing)
        db.session.flush()
    db.session.add(feedback)
    db.session.commit()
    return {"feedback": feedback.to_dict()}, 201
