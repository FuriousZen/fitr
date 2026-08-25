"""Weather passthrough.

Exists so the API key can live on the server rather than in the iOS bundle.
``Constants.swift`` resolves the key at run time from the scheme environment
or Info.plist, and anything in Info.plist ships inside the .ipa.
"""

from __future__ import annotations

from flask import Blueprint, request

from ..auth import require_user
from ..errors import ServiceUnavailable, ValidationError
from ..services import services
from ..services.weather import WeatherUnavailableError
from .helpers import get_float, get_str

bp = Blueprint("weather", __name__, url_prefix="/api/v1")


@bp.get("/weather")
@require_user
def get_weather():
    args = request.args.to_dict(flat=True)
    lat = get_float(args, "lat")
    lon = get_float(args, "lon")
    q = get_str(args, "q")
    units = get_str(args, "units") or None

    if not q and (lat is None or lon is None):
        raise ValidationError("provide q, or both lat and lon")

    try:
        result = services().weather.fetch(lat=lat, lon=lon, q=q or None, units=units)
    except WeatherUnavailableError as exc:
        raise ServiceUnavailable(str(exc)) from exc

    return {
        "weather": result.data,
        "cached": result.cached,
        "elapsed_ms": round(result.elapsed_ms, 2),
    }
