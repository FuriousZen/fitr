from __future__ import annotations

import pytest


def test_healthz_reports_live_database_and_pgvector(client):
    resp = client.get("/healthz")
    assert resp.status_code == 200
    body = resp.get_json()
    assert body["status"] == "ok"
    assert body["database"]["connected"] is True
    # Proves the tests really are running against pgvector, not a stub.
    assert body["database"]["pgvector"] is not None


def test_health_detail_reports_unconfigured_third_parties(client, auth):
    body = client.get("/api/v1/health", headers=auth).get_json()
    assert body["status"] == "ok"
    assert body["clip"]["dim"] == 512
    # No keys exist in this environment and the suite must not invent any.
    assert body["weather"]["configured"] is False
    assert body["gemini"]["configured"] is False
    assert body["config"]["auth_mode"] == "header"


@pytest.mark.parametrize(
    "method,path",
    [
        ("get", "/api/v1/wardrobe/items"),
        ("post", "/api/v1/wardrobe/search"),
        ("get", "/api/v1/weather?lat=1&lon=2"),
        ("post", "/api/v1/recommendations"),
        ("get", "/api/v1/metrics/acceptance"),
    ],
)
def test_endpoints_require_a_user(client, method, path):
    resp = getattr(client, method)(path)
    assert resp.status_code == 401
    assert resp.get_json()["error"]["code"] == "unauthorized"


def test_health_endpoints_are_public(client):
    assert client.get("/healthz").status_code == 200


def test_overlong_user_id_rejected(client):
    resp = client.get("/api/v1/wardrobe/items", headers={"X-User-Id": "x" * 200})
    assert resp.status_code == 401


def test_firebase_mode_rejects_a_garbage_token(app, client):
    """The firebase path has never been run against a real project here; this
    only asserts that an unverifiable token is refused rather than trusted."""
    app.config["AUTH_MODE"] = "firebase"
    app.config["FIREBASE_PROJECT_ID"] = "fitr-test-project"
    try:
        resp = client.get(
            "/api/v1/wardrobe/items", headers={"Authorization": "Bearer not.a.jwt"}
        )
        assert resp.status_code == 401
    finally:
        app.config["AUTH_MODE"] = "header"
        app.config["FIREBASE_PROJECT_ID"] = ""


def test_firebase_mode_requires_project_id(app, client):
    app.config["AUTH_MODE"] = "firebase"
    app.config["FIREBASE_PROJECT_ID"] = ""
    try:
        resp = client.get(
            "/api/v1/wardrobe/items", headers={"Authorization": "Bearer abc"}
        )
        assert resp.status_code == 401
        assert "FITR_FIREBASE_PROJECT_ID" in resp.get_json()["error"]["message"]
    finally:
        app.config["AUTH_MODE"] = "header"


def test_unknown_route_returns_json_error(client):
    resp = client.get("/api/v1/nope")
    assert resp.status_code == 404
    assert "error" in resp.get_json()
