from __future__ import annotations

import pytest
import responses

from app.services.recommender import build_query_text, temperature_band
from app.services.weather import BASE_URL

from .fakes import FakeGeminiClient
from .test_weather import OWM_PAYLOAD

COLD_RAIN = {
    "temperature": 42.0,
    "condition": "Rainy",
    "humidity": 88,
    "wind_speed": 9.0,
    "location": "Charlottesville",
    "units": "imperial",
}


@pytest.fixture
def wardrobe(make_item):
    return {
        "tee": make_item(name="white tee", type="T-Shirt", color="white"),
        "shirt": make_item(name="oxford shirt", type="Shirt", color="blue"),
        "jeans": make_item(name="blue jeans", type="Jeans", color="blue"),
        "shorts": make_item(name="khaki shorts", type="Shorts", color="khaki"),
        "jacket": make_item(name="rain jacket", type="Jacket", color="black"),
        "shoes": make_item(name="brown boots", type="Shoes", color="brown"),
    }


@pytest.mark.parametrize(
    "temp,units,band",
    [
        (90.0, "imperial", "Hot"),
        (70.0, "imperial", "Warm"),
        (55.0, "imperial", "Cool"),
        (20.0, "imperial", "Cold"),
        (30.0, "metric", "Hot"),
        (20.0, "metric", "Warm"),
        (12.0, "metric", "Cool"),
        (-5.0, "metric", "Cold"),
        (300.0, "standard", "Hot"),
        (260.0, "standard", "Cold"),
    ],
)
def test_temperature_banding_handles_every_unit_system(temp, units, band):
    assert temperature_band(temp, units) == band


def test_query_text_describes_the_situation():
    text = build_query_text("formal", COLD_RAIN)
    assert "formal" in text and "cold" in text and "rainy" in text


def test_recommendation_runs_end_to_end_without_gemini(client, auth, wardrobe):
    resp = client.post(
        "/api/v1/recommendations",
        json={"vibe": "casual", "weather": COLD_RAIN},
        headers=auth,
    )
    assert resp.status_code == 201
    body = resp.get_json()

    assert body["generator"] == "heuristic"
    assert body["options"], "the heuristic ranker must still produce an outfit"
    assert body["candidates"], "CLIP must have shortlisted candidates"
    assert body["timings_ms"]["clip"] >= 0
    assert body["timings_ms"]["retrieval"] >= 0
    for option in body["options"]:
        assert len(option["items"]) >= 2
        assert len(option["item_ids"]) == len(option["items"])


def test_shortlist_is_capped_by_candidate_k(client, auth, wardrobe):
    body = client.post(
        "/api/v1/recommendations",
        json={"vibe": "casual", "weather": COLD_RAIN, "candidate_k": 3},
        headers=auth,
    ).get_json()
    assert len(body["candidates"]) == 3
    assert len(body["candidate_item_ids"]) == 3


def test_dirty_items_are_excluded_by_default(client, auth, make_item):
    make_item(name="clean tee", type="T-Shirt")
    make_item(name="clean jeans", type="Jeans")
    dirty = make_item(name="dirty jacket", type="Jacket", dirty="true")

    body = client.post(
        "/api/v1/recommendations", json={"weather": COLD_RAIN}, headers=auth
    ).get_json()
    assert dirty["id"] not in body["candidate_item_ids"]


def test_dirty_items_can_be_included_explicitly(client, auth, make_item):
    dirty = make_item(name="dirty jacket", type="Jacket", dirty="true")
    make_item(name="clean tee", type="T-Shirt")

    body = client.post(
        "/api/v1/recommendations",
        json={"weather": COLD_RAIN, "include_dirty": True},
        headers=auth,
    ).get_json()
    assert dirty["id"] in body["candidate_item_ids"]


def test_empty_wardrobe_returns_no_options_rather_than_erroring(client, auth):
    body = client.post(
        "/api/v1/recommendations", json={"weather": COLD_RAIN}, headers=auth
    ).get_json()
    assert body["options"] == []
    assert body["generator"] == "none"


def test_gemini_path_is_used_when_configured(client, auth, services, wardrobe):
    services.gemini._client = FakeGeminiClient(
        responses=[
            {
                "options": [
                    {"item_ids": [wardrobe["tee"]["id"], wardrobe["jeans"]["id"]],
                     "description": "Tee and jeans, easy."},
                ]
            }
        ]
    )
    body = client.post(
        "/api/v1/recommendations", json={"vibe": "casual", "weather": COLD_RAIN}, headers=auth
    ).get_json()

    assert body["generator"] == "gemini"
    assert body["model"] == services.gemini.model
    assert body["options"][0]["description"] == "Tee and jeans, easy."
    assert body["timings_ms"]["generation"] >= 0


def test_gemini_only_sees_the_clip_shortlist(client, auth, services, wardrobe):
    fake = FakeGeminiClient(responses=[{"options": [{"item_ids": [wardrobe["tee"]["id"]],
                                                    "description": "x"}]}])
    services.gemini._client = fake
    body = client.post(
        "/api/v1/recommendations",
        json={"weather": COLD_RAIN, "candidate_k": 2},
        headers=auth,
    ).get_json()

    prompt = fake.calls[0]["contents"]
    shortlisted = set(body["candidate_item_ids"])
    assert len(shortlisted) == 2
    for item in wardrobe.values():
        assert (item["id"] in prompt) == (item["id"] in shortlisted)


def test_gemini_failure_falls_back_to_the_heuristic(client, auth, services, wardrobe):
    services.gemini._client = FakeGeminiClient(raises=RuntimeError("503 from Google"))
    body = client.post(
        "/api/v1/recommendations", json={"weather": COLD_RAIN}, headers=auth
    ).get_json()

    assert body["generator"] == "heuristic"
    assert body["options"], "a third-party outage must not empty the response"


def test_gemini_returning_nothing_falls_back_and_says_so(client, auth, services, wardrobe):
    services.gemini._client = FakeGeminiClient(responses=[{"options": []}])
    body = client.post(
        "/api/v1/recommendations", json={"weather": COLD_RAIN}, headers=auth
    ).get_json()
    assert body["generator"] == "gemini_empty_fallback"
    assert body["options"]


@responses.activate
def test_weather_is_fetched_from_coordinates_when_not_supplied(
    client, auth, services, wardrobe
):
    responses.add(responses.GET, BASE_URL, json=OWM_PAYLOAD, status=200)
    services.weather.api_key = "test-key"

    body = client.post(
        "/api/v1/recommendations",
        json={"vibe": "casual", "lat": 38.03, "lon": -78.48},
        headers=auth,
    ).get_json()

    assert body["weather"]["location"] == "Charlottesville"
    assert body["weather"]["condition"] == "Rainy"
    assert body["timings_ms"]["weather"] >= 0


def test_missing_location_and_weather_is_a_validation_error(client, auth, wardrobe):
    resp = client.post("/api/v1/recommendations", json={"vibe": "casual"}, headers=auth)
    assert resp.status_code == 422


def test_location_without_a_weather_key_is_503(client, auth, wardrobe):
    resp = client.post(
        "/api/v1/recommendations", json={"lat": 38.03, "lon": -78.48}, headers=auth
    )
    assert resp.status_code == 503


@pytest.mark.parametrize(
    "weather",
    [
        {"temperature": "not-a-number"},
        {"temperature": None},
        {"temperature": 70.0, "condition": {"nested": "object"}},
        {"temperature": 70.0, "units": 123},
        {"temperature": 70.0, "units": "fahrenheit"},
    ],
)
def test_malformed_weather_object_is_422_not_500(client, auth, wardrobe, weather):
    resp = client.post("/api/v1/recommendations", json={"weather": weather}, headers=auth)
    assert resp.status_code == 422, resp.get_json()


def test_recommendation_is_persisted_and_retrievable(client, auth, wardrobe):
    created = client.post(
        "/api/v1/recommendations", json={"weather": COLD_RAIN}, headers=auth
    ).get_json()
    fetched = client.get(f"/api/v1/recommendations/{created['id']}", headers=auth).get_json()
    assert fetched["id"] == created["id"]
    assert fetched["query_text"] == created["query_text"]


def test_recommendations_are_private(client, auth, other_auth, wardrobe):
    created = client.post(
        "/api/v1/recommendations", json={"weather": COLD_RAIN}, headers=auth
    ).get_json()
    assert client.get(
        f"/api/v1/recommendations/{created['id']}", headers=other_auth
    ).status_code == 404


# -- feedback -------------------------------------------------------------


@pytest.fixture
def recommendation(client, auth, wardrobe):
    return client.post(
        "/api/v1/recommendations", json={"weather": COLD_RAIN, "num_options": 3}, headers=auth
    ).get_json()


def test_feedback_is_recorded(client, auth, recommendation):
    resp = client.post(
        f"/api/v1/recommendations/{recommendation['id']}/feedback",
        json={"accepted": True, "accepted_rank": 1, "note": "wore it"},
        headers=auth,
    )
    assert resp.status_code == 201
    body = resp.get_json()["feedback"]
    assert body["accepted"] is True
    assert body["accepted_rank"] == 1
    assert body["note"] == "wore it"


def test_rejection_needs_no_rank(client, auth, recommendation):
    resp = client.post(
        f"/api/v1/recommendations/{recommendation['id']}/feedback",
        json={"accepted": False},
        headers=auth,
    )
    assert resp.status_code == 201
    assert resp.get_json()["feedback"]["accepted_rank"] is None


def test_acceptance_requires_a_rank(client, auth, recommendation):
    resp = client.post(
        f"/api/v1/recommendations/{recommendation['id']}/feedback",
        json={"accepted": True},
        headers=auth,
    )
    assert resp.status_code == 422


def test_rank_beyond_the_offered_options_is_rejected(client, auth, recommendation):
    offered = len(recommendation["options"])
    resp = client.post(
        f"/api/v1/recommendations/{recommendation['id']}/feedback",
        json={"accepted": True, "accepted_rank": offered + 5},
        headers=auth,
    )
    assert resp.status_code == 422


def test_accepted_field_is_required(client, auth, recommendation):
    resp = client.post(
        f"/api/v1/recommendations/{recommendation['id']}/feedback", json={}, headers=auth
    )
    assert resp.status_code == 422


def test_feedback_can_be_revised(client, auth, recommendation):
    url = f"/api/v1/recommendations/{recommendation['id']}/feedback"
    client.post(url, json={"accepted": False}, headers=auth)
    client.post(url, json={"accepted": True, "accepted_rank": 1}, headers=auth)

    body = client.get("/api/v1/metrics/acceptance", headers=auth).get_json()
    assert body["recommendations_with_feedback"] == 1, "one row per recommendation"
    assert body["accepted_within_top_k"] == 1


def test_feedback_on_someone_elses_recommendation_is_404(client, other_auth, recommendation):
    resp = client.post(
        f"/api/v1/recommendations/{recommendation['id']}/feedback",
        json={"accepted": True, "accepted_rank": 1},
        headers=other_auth,
    )
    assert resp.status_code == 404


def test_feedback_on_a_missing_recommendation_is_404(client, auth):
    resp = client.post(
        "/api/v1/recommendations/nope/feedback", json={"accepted": False}, headers=auth
    )
    assert resp.status_code == 404
