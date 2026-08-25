"""OpenWeatherMap client.

Endpoint per https://openweathermap.org/current :

    https://api.openweathermap.org/data/2.5/weather?lat={lat}&lon={lon}&appid={key}
    https://api.openweathermap.org/data/2.5/weather?q={city}&appid={key}

``units`` is one of ``standard`` (Kelvin, default), ``metric`` (C), ``imperial``
(F). The iOS app has always used ``imperial``, so that is the default here.

Responses are cached in-process with a TTL (default 1 h), keyed on the rounded
coordinate or the city string, matching and replacing the 1-hour cache that
``WeatherService.swift`` did client-side.
"""

from __future__ import annotations

import threading
import time
from dataclasses import dataclass

import requests

BASE_URL = "https://api.openweathermap.org/data/2.5/weather"

#: OpenWeatherMap ``weather[].main`` -> the Swift ``WeatherCondition`` raw value.
_CONDITION_MAP = {
    "clear": "Sunny",
    "clouds": "Cloudy",
    "rain": "Rainy",
    "drizzle": "Rainy",
    "snow": "Snowy",
    "thunderstorm": "Stormy",
    "mist": "Foggy",
    "fog": "Foggy",
    "haze": "Foggy",
    "smoke": "Foggy",
    "dust": "Foggy",
    "sand": "Foggy",
    "ash": "Foggy",
    "squall": "Windy",
    "tornado": "Stormy",
}


def map_condition(main: str | None) -> str:
    if not main:
        return "Cloudy"
    lowered = main.strip().lower()
    if lowered in _CONDITION_MAP:
        return _CONDITION_MAP[lowered]
    if "wind" in lowered:
        return "Windy"
    return "Cloudy"


class WeatherUnavailableError(RuntimeError):
    pass


@dataclass(frozen=True)
class WeatherResult:
    data: dict
    cached: bool
    elapsed_ms: float


class WeatherService:
    def __init__(
        self,
        api_key: str = "",
        units: str = "imperial",
        ttl_seconds: int = 3600,
        timeout_s: float = 10.0,
        session: requests.Session | None = None,
    ) -> None:
        self.api_key = api_key or ""
        self.units = units
        self.ttl_seconds = ttl_seconds
        self.timeout_s = timeout_s
        self._session = session or requests.Session()
        self._cache: dict[str, tuple[float, dict]] = {}
        self._lock = threading.Lock()

    @property
    def configured(self) -> bool:
        return bool(self.api_key)

    # -- cache -------------------------------------------------------------

    @staticmethod
    def _key(lat: float | None, lon: float | None, q: str | None, units: str) -> str:
        if q:
            return f"q:{q.strip().lower()}:{units}"
        # Two decimal places is ~1.1 km: finer than weather varies, coarse
        # enough that a phone's jittering GPS still hits the same cache entry.
        return f"c:{round(float(lat), 2)}:{round(float(lon), 2)}:{units}"

    def _cache_get(self, key: str) -> dict | None:
        with self._lock:
            entry = self._cache.get(key)
            if entry is None:
                return None
            stored_at, payload = entry
            if (time.time() - stored_at) > self.ttl_seconds:
                self._cache.pop(key, None)
                return None
            return payload

    def _cache_put(self, key: str, payload: dict) -> None:
        with self._lock:
            self._cache[key] = (time.time(), payload)

    def clear_cache(self) -> None:
        with self._lock:
            self._cache.clear()

    # -- fetch -------------------------------------------------------------

    def fetch(
        self,
        lat: float | None = None,
        lon: float | None = None,
        q: str | None = None,
        units: str | None = None,
    ) -> WeatherResult:
        if not self.configured:
            raise WeatherUnavailableError(
                "OPENWEATHERMAP_API_KEY is not set; weather lookups are disabled"
            )
        if q is None and (lat is None or lon is None):
            raise ValueError("provide either q, or both lat and lon")

        units = units or self.units
        key = self._key(lat, lon, q, units)
        started = time.perf_counter()

        cached = self._cache_get(key)
        if cached is not None:
            return WeatherResult(
                data=cached, cached=True, elapsed_ms=(time.perf_counter() - started) * 1000.0
            )

        params: dict[str, object] = {"appid": self.api_key, "units": units}
        if q:
            params["q"] = q
        else:
            params["lat"] = lat
            params["lon"] = lon

        try:
            resp = self._session.get(BASE_URL, params=params, timeout=self.timeout_s)
        except requests.RequestException as exc:
            raise WeatherUnavailableError(f"weather request failed: {exc}") from exc

        if resp.status_code == 401:
            raise WeatherUnavailableError("OpenWeatherMap rejected the API key (401)")
        if resp.status_code == 404:
            raise WeatherUnavailableError(f"location not found: {q or (lat, lon)}")
        if resp.status_code >= 400:
            raise WeatherUnavailableError(
                f"OpenWeatherMap returned HTTP {resp.status_code}: {resp.text[:200]}"
            )

        payload = self.normalize(resp.json(), units=units)
        self._cache_put(key, payload)
        return WeatherResult(
            data=payload, cached=False, elapsed_ms=(time.perf_counter() - started) * 1000.0
        )

    @staticmethod
    def normalize(raw: dict, units: str = "imperial") -> dict:
        """Reshape an OWM payload into the Swift ``Weather`` struct's JSON form."""
        weather_list = raw.get("weather") or [{}]
        first = weather_list[0] if weather_list else {}
        main = raw.get("main") or {}
        wind = raw.get("wind") or {}
        return {
            "temperature": float(main.get("temp", 0.0)),
            "condition": map_condition(first.get("main")),
            "description": first.get("description", ""),
            "humidity": int(main.get("humidity", 0)),
            "wind_speed": float(wind.get("speed", 0.0)),
            "location": raw.get("name", "") or "",
            "units": units,
        }

    def health(self) -> dict:
        return {
            "configured": self.configured,
            "units": self.units,
            "ttl_seconds": self.ttl_seconds,
            "cached_locations": len(self._cache),
        }
