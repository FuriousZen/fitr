"""Metrics tests.

The central assertion here is negative: with no feedback submitted, the
acceptance rate must be ``null``. An unmeasured rate must never be reported as
a number.
"""

from __future__ import annotations

import pytest

from app.api.metrics import _percentile

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
    """Wide enough to actually yield three distinct options.

    The heuristic ranker builds one outfit per (top, bottom) pairing, so a
    wardrobe with a single top can only ever produce a single option. Three
    tops and three bottoms are needed before an ``accepted_rank`` of 3 is a
    valid thing for a user to report.
    """
    for i in range(3):
        make_item(name=f"tee {i}", type="T-Shirt")
        make_item(name=f"jeans {i}", type="Jeans")
    make_item(name="rain jacket", type="Jacket")
    make_item(name="brown boots", type="Shoes")


def _recommend(client, auth, expect_options: int | None = None):
    body = client.post(
        "/api/v1/recommendations",
        json={"weather": COLD_RAIN, "num_options": 3, "candidate_k": 20},
        headers=auth,
    ).get_json()
    if expect_options is not None:
        assert len(body["options"]) == expect_options, body["options"]
    return body


def test_acceptance_is_null_with_no_feedback(client, auth):
    body = client.get("/api/v1/metrics/acceptance", headers=auth).get_json()
    assert body["top_k_acceptance"] is None
    assert body["recommendations_with_feedback"] == 0
    assert body["note"], "a null rate must explain itself"


def test_acceptance_stays_null_when_recommendations_exist_but_feedback_does_not(
    client, auth, wardrobe
):
    _recommend(client, auth)
    body = client.get("/api/v1/metrics/acceptance", headers=auth).get_json()
    assert body["total_recommendations"] == 1
    assert body["top_k_acceptance"] is None


def test_acceptance_is_computed_from_submitted_feedback(client, auth, wardrobe):
    outcomes = [
        (True, 1),
        (True, 2),
        (True, 3),
        (False, None),
    ]
    for accepted, rank in outcomes:
        rec = _recommend(client, auth)
        payload = {"accepted": accepted}
        if rank:
            payload["accepted_rank"] = rank
        client.post(
            f"/api/v1/recommendations/{rec['id']}/feedback", json=payload, headers=auth
        )

    body = client.get("/api/v1/metrics/acceptance?top_k=3", headers=auth).get_json()
    assert body["recommendations_with_feedback"] == 4
    assert body["accepted_within_top_k"] == 3
    assert body["top_k_acceptance"] == 0.75
    assert body["note"] is None


def test_top_k_narrows_the_numerator(client, auth, wardrobe):
    for rank in (1, 2, 3):
        rec = _recommend(client, auth)
        client.post(
            f"/api/v1/recommendations/{rec['id']}/feedback",
            json={"accepted": True, "accepted_rank": rank},
            headers=auth,
        )

    top1 = client.get("/api/v1/metrics/acceptance?top_k=1", headers=auth).get_json()
    top3 = client.get("/api/v1/metrics/acceptance?top_k=3", headers=auth).get_json()
    assert top1["accepted_within_top_k"] == 1
    assert top3["accepted_within_top_k"] == 3
    assert top1["top_k_acceptance"] < top3["top_k_acceptance"]


def test_distinct_users_are_counted(client, auth, other_auth, make_item, wardrobe):
    rec = _recommend(client, auth)
    client.post(
        f"/api/v1/recommendations/{rec['id']}/feedback",
        json={"accepted": True, "accepted_rank": 1},
        headers=auth,
    )
    body = client.get("/api/v1/metrics/acceptance", headers=auth).get_json()
    assert body["distinct_users_with_feedback"] == 1


def test_latency_is_null_with_no_data(client, auth):
    body = client.get("/api/v1/metrics/latency", headers=auth).get_json()
    assert body["samples"] == 0
    assert body["total_ms"] is None


def test_latency_reports_percentiles_and_a_breakdown(client, auth, wardrobe):
    for _ in range(5):
        _recommend(client, auth)

    body = client.get("/api/v1/metrics/latency", headers=auth).get_json()
    assert body["samples"] == 5
    assert body["total_ms"]["p50"] >= 0
    assert body["total_ms"]["p95"] >= body["total_ms"]["p50"]
    assert body["total_ms"]["max"] >= body["total_ms"]["p95"]
    assert set(body["breakdown_ms"]) == {"weather", "clip", "retrieval", "generation"}


def test_latency_can_be_filtered_by_generator(client, auth, wardrobe):
    _recommend(client, auth)
    assert client.get(
        "/api/v1/metrics/latency?generator=heuristic", headers=auth
    ).get_json()["samples"] == 1
    assert client.get(
        "/api/v1/metrics/latency?generator=gemini", headers=auth
    ).get_json()["samples"] == 0


@pytest.mark.parametrize(
    "values,pct,expected",
    [
        ([], 50, None),
        ([10.0], 50, 10.0),
        ([1.0, 2.0, 3.0, 4.0], 50, 2.0),
        ([1.0, 2.0, 3.0, 4.0], 100, 4.0),
        (list(range(1, 101)), 95, 95.0),
    ],
)
def test_percentile_is_nearest_rank(values, pct, expected):
    """Nearest-rank, so every reported percentile is a real observation rather
    than an interpolated value that never occurred."""
    assert _percentile([float(v) for v in values], pct) == expected


def test_cache_metrics_expose_both_tiers(client, auth, wardrobe):
    body = client.get("/api/v1/metrics/cache", headers=auth).get_json()
    assert body["process_cache"]["l1_entries"] >= 1
    assert body["postgres_cache"]["rows"] >= 1
    assert body["postgres_cache"]["mean_cold_compute_ms"] is not None


def test_cache_metrics_are_empty_before_any_upload(client, auth):
    body = client.get("/api/v1/metrics/cache", headers=auth).get_json()
    assert body["postgres_cache"]["rows"] == 0
    assert body["postgres_cache"]["mean_cold_compute_ms"] is None
    assert body["process_cache"]["hit_rate"] is None
