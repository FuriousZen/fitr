"""Cache-tier behaviour: the mechanism behind the cold/warm latency claim."""

from __future__ import annotations

from app.models import ImageEmbedding
from app.services.embedding_cache import L1, L2, MISS, content_hash

from .conftest import make_image


def test_first_call_computes_then_l1_serves(app, services):
    image = make_image(label="a")

    first = services.cache.get_or_compute(image)
    assert first.tier == MISS
    assert services.encoder.image_calls == 1

    second = services.cache.get_or_compute(image)
    assert second.tier == L1
    # The whole point: a cache hit must not re-run the model.
    assert services.encoder.image_calls == 1
    assert (first.vector == second.vector).all()


def test_l2_serves_after_process_cache_is_dropped(app, services):
    image = make_image(label="b")
    services.cache.get_or_compute(image)
    assert services.encoder.image_calls == 1

    # Simulate a worker restart / a second gunicorn worker.
    services.cache.clear_l1()

    result = services.cache.get_or_compute(image)
    assert result.tier == L2
    assert services.encoder.image_calls == 1, "L2 hit must not recompute"


def test_l2_row_records_the_cold_compute_cost(app, services):
    from app.extensions import db

    image = make_image(label="c")
    result = services.cache.get_or_compute(image)
    row = db.session.get(ImageEmbedding, (result.content_hash, services.encoder.model_id))
    assert row is not None
    assert row.dim == 512
    assert row.compute_ms is not None and row.compute_ms >= 0


def test_l2_hit_count_increments(app, services):
    from app.extensions import db

    image = make_image(label="d")
    digest = content_hash(image)
    services.cache.get_or_compute(image)

    for _ in range(3):
        services.cache.clear_l1()
        services.cache.get_or_compute(image)

    row = db.session.get(ImageEmbedding, (digest, services.encoder.model_id))
    assert row.hit_count == 3


def test_cache_is_content_addressed_not_filename_addressed(app, services):
    image = make_image(label="same")
    services.cache.get_or_compute(image)
    # Identical bytes arriving from a different "file" still hit.
    assert services.cache.get_or_compute(bytes(image)).tier == L1
    assert services.encoder.image_calls == 1


def test_different_images_do_not_collide(app, services):
    a = services.cache.get_or_compute(make_image(label="one"))
    b = services.cache.get_or_compute(make_image(label="two"))
    assert a.content_hash != b.content_hash
    assert services.encoder.image_calls == 2


def test_switching_model_id_invalidates_the_cache(app, services):
    """A vector from another model must never be served as this model's."""
    image = make_image(label="model-switch")
    services.cache.get_or_compute(image)

    services.encoder.model_id = "fake/clip-other"
    services.cache.clear_l1()

    result = services.cache.get_or_compute(image)
    assert result.tier == MISS
    assert services.encoder.image_calls == 2


def test_l1_evicts_least_recently_used(app, services):
    services.cache.max_entries = 2
    images = [make_image(label=f"lru{i}") for i in range(3)]
    for image in images:
        services.cache.get_or_compute(image)

    assert len(services.cache._l1) == 2
    # images[0] was evicted, so it falls through to Postgres, not to the model.
    assert services.cache.get_or_compute(images[0]).tier == L2
    assert services.encoder.image_calls == 3


def test_peek_tier_does_not_mutate(app, services):
    image = make_image(label="peek")
    assert services.cache.peek_tier(image) == MISS
    assert services.encoder.image_calls == 0
    services.cache.get_or_compute(image)
    assert services.cache.peek_tier(image) == L1


def test_health_counts_hits_and_misses(app, services):
    image = make_image(label="stats")
    services.cache.get_or_compute(image)
    services.cache.get_or_compute(image)
    health = services.cache.health()
    assert health["misses"] == 1
    assert health["hits_l1"] == 1
    assert health["hit_rate"] == 0.5


def test_embeddings_endpoint_reports_its_tier(client, auth, upload):
    image = make_image(label="endpoint")

    def post():
        return client.post(
            "/api/v1/embeddings",
            data=upload(image),
            headers=auth,
            content_type="multipart/form-data",
        ).get_json()

    first, second = post(), post()
    assert first["cache_tier"] == MISS
    assert second["cache_tier"] == L1
    assert first["dim"] == 512
    assert second["elapsed_ms"] <= first["elapsed_ms"]


def test_embeddings_endpoint_can_return_the_vector(client, auth):
    import base64

    image = make_image(label="vector")
    resp = client.post(
        "/api/v1/embeddings",
        json={
            "image_base64": base64.b64encode(image).decode(),
            "include_vector": True,
        },
        headers=auth,
    )
    body = resp.get_json()
    assert len(body["embedding"]) == 512
    norm = sum(x * x for x in body["embedding"]) ** 0.5
    assert abs(norm - 1.0) < 1e-4, "vectors must be L2-normalised before storage"


def test_data_url_base64_is_accepted(client, auth):
    import base64

    encoded = base64.b64encode(make_image(label="dataurl")).decode()
    resp = client.post(
        "/api/v1/embeddings",
        json={"image_base64": f"data:image/jpeg;base64,{encoded}"},
        headers=auth,
    )
    assert resp.status_code == 200


def test_non_image_bytes_are_rejected(client, auth):
    import base64

    resp = client.post(
        "/api/v1/embeddings",
        json={"image_base64": base64.b64encode(b"definitely not an image").decode()},
        headers=auth,
    )
    assert resp.status_code == 422


def test_missing_image_is_rejected(client, auth):
    resp = client.post("/api/v1/embeddings", json={}, headers=auth)
    assert resp.status_code == 422


def test_oversized_image_is_rejected(app, client, auth, upload):
    app.config["MAX_IMAGE_BYTES"] = 100
    try:
        resp = client.post(
            "/api/v1/embeddings",
            data=upload(make_image(label="big")),
            headers=auth,
            content_type="multipart/form-data",
        )
        assert resp.status_code == 413
    finally:
        app.config["MAX_IMAGE_BYTES"] = 10 * 1024 * 1024
