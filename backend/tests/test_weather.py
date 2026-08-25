"""Weather client tests.

There is no OpenWeatherMap key in this environment, so every HTTP interaction
is intercepted by ``responses``. The payloads below are shaped from the
documented schema at https://openweathermap.org/current. They are constructed
fixtures, not recordings of real traffic.
"""

from __future__ import annotations

import pytest
import responses

from app.services.weather import (
    BASE_URL,
    WeatherService,
    WeatherUnavailableError,
    map_condition,
)

OWM_PAYLOAD = {
    "coord": {"lon": -78.4767, "lat": 38.0293},
    "weather": [{"id": 500, "main": "Rain", "description": "light rain", "icon": "10d"}],
    "base": "stations",
    "main": {
        "temp": 48.2,
        "feels_like": 45.1,
        "temp_min": 46.0,
        "temp_max": 50.0,
        "pressure": 1015,
        "humidity": 82,
    },
    "visibility": 10000,
    "wind": {"speed": 7.6, "deg": 210},
    "clouds": {"all": 90},
    "dt": 1_744_000_000,
    "sys": {"country": "US", "sunrise": 1, "sunset": 2},
    "timezone": -14400,
    "id": 4752031,
    "name": "Charlottesville",
    "cod": 200,
}


@pytest.mark.parametrize(
    "owm_main,expected",
    [
        ("Clear", "Sunny"),
        ("Clouds", "Cloudy"),
        ("Rain", "Rainy"),
        ("Drizzle", "Rainy"),
        ("Snow", "Snowy"),
        ("Thunderstorm", "Stormy"),
        ("Mist", "Foggy"),
        ("Fog", "Foggy"),
        ("Squall", "Windy"),
        ("Tornado", "Stormy"),
        ("Something Windy", "Windy"),
        ("Unrecognised", "Cloudy"),
        (None, "Cloudy"),
    ],
)
def test_condition_mapping_matches_the_swift_enum(owm_main, expected):
    assert map_condition(owm_main) == expected


def test_normalize_produces_the_swift_weather_shape():
    out = WeatherService.normalize(OWM_PAYLOAD, units="imperial")
    assert out == {
        "temperature": 48.2,
        "condition": "Rainy",
        "description": "light rain",
        "humidity": 82,
        "wind_speed": 7.6,
        "location": "Charlottesville",
        "units": "imperial",
    }


def test_normalize_tolerates_a_sparse_payload():
    out = WeatherService.normalize({}, units="metric")
    assert out["temperature"] == 0.0
    assert out["condition"] == "Cloudy"
    assert out["units"] == "metric"


@responses.activate
def test_fetch_by_coordinates_sends_the_documented_parameters():
    responses.add(responses.GET, BASE_URL, json=OWM_PAYLOAD, status=200)
    svc = WeatherService(api_key="test-key", units="imperial")

    result = svc.fetch(lat=38.0293, lon=-78.4767)

    assert result.cached is False
    assert result.data["condition"] == "Rainy"
    request = responses.calls[0].request
    assert "lat=38.0293" in request.url
    assert "lon=-78.4767" in request.url
    assert "units=imperial" in request.url
    assert "appid=test-key" in request.url


@responses.activate
def test_fetch_by_city_name():
    responses.add(responses.GET, BASE_URL, json=OWM_PAYLOAD, status=200)
    svc = WeatherService(api_key="test-key")
    svc.fetch(q="Charlottesville,VA,US")
    assert "q=Charlottesville" in responses.calls[0].request.url


@responses.activate
def test_second_lookup_is_served_from_cache():
    responses.add(responses.GET, BASE_URL, json=OWM_PAYLOAD, status=200)
    svc = WeatherService(api_key="test-key", ttl_seconds=3600)

    first = svc.fetch(lat=38.03, lon=-78.48)
    second = svc.fetch(lat=38.03, lon=-78.48)

    assert first.cached is False
    assert second.cached is True
    assert len(responses.calls) == 1, "a cache hit must not call OpenWeatherMap"


@responses.activate
def test_nearby_coordinates_share_a_cache_entry():
    """GPS jitter of a few metres should not cost an API call."""
    responses.add(responses.GET, BASE_URL, json=OWM_PAYLOAD, status=200)
    svc = WeatherService(api_key="test-key")
    svc.fetch(lat=38.0293, lon=-78.4767)
    svc.fetch(lat=38.0294, lon=-78.4768)
    assert len(responses.calls) == 1


@responses.activate
def test_distant_coordinates_do_not_share_a_cache_entry():
    responses.add(responses.GET, BASE_URL, json=OWM_PAYLOAD, status=200)
    svc = WeatherService(api_key="test-key")
    svc.fetch(lat=38.03, lon=-78.48)
    svc.fetch(lat=40.71, lon=-74.01)
    assert len(responses.calls) == 2


@responses.activate
def test_expired_cache_entry_is_refetched():
    responses.add(responses.GET, BASE_URL, json=OWM_PAYLOAD, status=200)
    svc = WeatherService(api_key="test-key", ttl_seconds=0)
    svc.fetch(lat=38.03, lon=-78.48)
    svc.fetch(lat=38.03, lon=-78.48)
    assert len(responses.calls) == 2


@responses.activate
def test_units_are_part_of_the_cache_key():
    responses.add(responses.GET, BASE_URL, json=OWM_PAYLOAD, status=200)
    svc = WeatherService(api_key="test-key")
    svc.fetch(lat=38.03, lon=-78.48, units="imperial")
    svc.fetch(lat=38.03, lon=-78.48, units="metric")
    assert len(responses.calls) == 2


@responses.activate
@pytest.mark.parametrize(
    "status,fragment", [(401, "rejected the API key"), (404, "not found"), (500, "HTTP 500")]
)
def test_http_errors_become_clear_messages(status, fragment):
    responses.add(responses.GET, BASE_URL, json={}, status=status)
    svc = WeatherService(api_key="test-key")
    with pytest.raises(WeatherUnavailableError) as exc:
        svc.fetch(lat=1.0, lon=2.0)
    assert fragment in str(exc.value)


def test_missing_key_is_reported_not_guessed():
    svc = WeatherService(api_key="")
    assert svc.configured is False
    with pytest.raises(WeatherUnavailableError, match="OPENWEATHERMAP_API_KEY"):
        svc.fetch(lat=1.0, lon=2.0)


def test_fetch_needs_a_location():
    svc = WeatherService(api_key="test-key")
    with pytest.raises(ValueError):
        svc.fetch()


@responses.activate
def test_weather_endpoint_returns_the_normalized_payload(app, client, auth, services):
    responses.add(responses.GET, BASE_URL, json=OWM_PAYLOAD, status=200)
    services.weather.api_key = "test-key"

    body = client.get("/api/v1/weather?lat=38.03&lon=-78.48", headers=auth).get_json()
    assert body["weather"]["condition"] == "Rainy"
    assert body["cached"] is False

    assert client.get("/api/v1/weather?lat=38.03&lon=-78.48", headers=auth).get_json()["cached"]


def test_weather_endpoint_requires_a_location(client, auth):
    assert client.get("/api/v1/weather", headers=auth).status_code == 422


def test_weather_endpoint_503s_without_a_key(client, auth):
    resp = client.get("/api/v1/weather?lat=1&lon=2", headers=auth)
    assert resp.status_code == 503
    assert resp.get_json()["error"]["code"] == "service_unavailable"
