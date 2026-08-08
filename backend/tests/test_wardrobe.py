from __future__ import annotations

from .conftest import make_image


def test_create_item_stores_an_embedding(client, auth, upload):
    resp = client.post(
        "/api/v1/wardrobe/items",
        data=upload(
            make_image(label="tee"),
            name="white tee",
            type="T-Shirt",
            color="white",
            weather_tags="Warm,Hot",
            style_tags="casual,everyday",
        ),
        headers=auth,
        content_type="multipart/form-data",
    )
    assert resp.status_code == 201
    body = resp.get_json()
    item = body["item"]
    assert item["has_embedding"] is True
    assert item["content_hash"]
    assert item["weather_tags"] == ["Warm", "Hot"]
    assert item["style_tags"] == ["casual", "everyday"]
    assert body["embedding_cache_tier"] == "miss"


def test_item_can_be_created_without_an_image(client, auth):
    resp = client.post(
        "/api/v1/wardrobe/items", json={"name": "socks", "type": "Accessory"}, headers=auth
    )
    assert resp.status_code == 201
    assert resp.get_json()["item"]["has_embedding"] is False


def test_unknown_type_falls_back_to_other(client, auth):
    body = client.post(
        "/api/v1/wardrobe/items", json={"name": "x", "type": "Spacesuit"}, headers=auth
    ).get_json()
    assert body["item"]["type"] == "Other"


def test_unknown_tags_are_dropped(client, auth):
    body = client.post(
        "/api/v1/wardrobe/items",
        json={"name": "x", "weather_tags": ["Hot", "Volcanic"], "style_tags": ["casual", "goth"]},
        headers=auth,
    ).get_json()
    assert body["item"]["weather_tags"] == ["Hot"]
    assert body["item"]["style_tags"] == ["casual"]


def test_client_supplied_id_is_honoured(client, auth):
    body = client.post(
        "/api/v1/wardrobe/items",
        json={"id": "firestore-doc-123", "name": "x"},
        headers=auth,
    ).get_json()
    assert body["item"]["id"] == "firestore-doc-123"


def test_list_filters_by_dirty_and_type(client, auth, make_item):
    make_item(name="clean tee", type="T-Shirt")
    make_item(name="dirty jeans", type="Jeans", dirty="true")

    all_items = client.get("/api/v1/wardrobe/items", headers=auth).get_json()
    assert all_items["count"] == 2

    clean = client.get("/api/v1/wardrobe/items?dirty=false", headers=auth).get_json()
    assert [i["name"] for i in clean["items"]] == ["clean tee"]

    jeans = client.get("/api/v1/wardrobe/items?type=Jeans", headers=auth).get_json()
    assert [i["name"] for i in jeans["items"]] == ["dirty jeans"]


def test_users_cannot_see_or_touch_each_others_items(client, auth, other_auth, make_item):
    item = make_item(name="private")

    assert client.get("/api/v1/wardrobe/items", headers=other_auth).get_json()["count"] == 0
    assert client.get(f"/api/v1/wardrobe/items/{item['id']}", headers=other_auth).status_code == 404
    assert client.patch(
        f"/api/v1/wardrobe/items/{item['id']}", json={"name": "hacked"}, headers=other_auth
    ).status_code == 404
    assert client.delete(
        f"/api/v1/wardrobe/items/{item['id']}", headers=other_auth
    ).status_code == 404
    # And the owner still has it untouched.
    assert client.get(f"/api/v1/wardrobe/items/{item['id']}", headers=auth).get_json()["item"][
        "name"
    ] == "private"


def test_patch_updates_fields(client, auth, make_item):
    item = make_item(name="before", color="blue")
    body = client.patch(
        f"/api/v1/wardrobe/items/{item['id']}",
        json={"name": "after", "dirty": True, "style_tags": ["formal"]},
        headers=auth,
    ).get_json()
    assert body["item"]["name"] == "after"
    assert body["item"]["dirty"] is True
    assert body["item"]["style_tags"] == ["formal"]
    assert body["item"]["color"] == "blue", "unspecified fields must be left alone"


def test_delete_removes_the_item(client, auth, make_item):
    item = make_item(name="doomed")
    assert client.delete(f"/api/v1/wardrobe/items/{item['id']}", headers=auth).status_code == 200
    assert client.get(f"/api/v1/wardrobe/items/{item['id']}", headers=auth).status_code == 404


def test_delete_keeps_the_shared_embedding_cache_entry(client, auth, upload, services):
    """The cache is content-addressed and global; deleting one item must not
    evict a vector another item or user may still need."""
    image = make_image(label="shared")
    created = client.post(
        "/api/v1/wardrobe/items",
        data=upload(image, name="a"),
        headers=auth,
        content_type="multipart/form-data",
    ).get_json()

    client.delete(f"/api/v1/wardrobe/items/{created['item']['id']}", headers=auth)
    services.cache.clear_l1()

    assert services.cache.get_or_compute(image).tier == "l2"


def test_wash_clears_dirty_in_bulk(client, auth, make_item):
    a = make_item(name="a", dirty="true")
    b = make_item(name="b", dirty="true")
    body = client.post(
        "/api/v1/wardrobe/wash", json={"item_ids": [a["id"], b["id"]]}, headers=auth
    ).get_json()
    assert body["count"] == 2
    clean = client.get("/api/v1/wardrobe/items?dirty=false", headers=auth).get_json()
    assert clean["count"] == 2


def test_wash_requires_item_ids(client, auth):
    assert client.post("/api/v1/wardrobe/wash", json={}, headers=auth).status_code == 422


def test_wash_ignores_other_users_items(client, auth, other_auth, make_item):
    mine = make_item(name="mine", dirty="true")
    body = client.post(
        "/api/v1/wardrobe/wash", json={"item_ids": [mine["id"]]}, headers=other_auth
    ).get_json()
    assert body["count"] == 0


def test_similar_returns_nearest_neighbours_in_distance_order(client, auth, make_item):
    target = make_item(name="target")
    for i in range(4):
        make_item(name=f"other{i}")

    body = client.get(f"/api/v1/wardrobe/items/{target['id']}/similar?k=3", headers=auth).get_json()
    assert body["query_item_id"] == target["id"]
    assert len(body["results"]) == 3
    assert target["id"] not in [r["id"] for r in body["results"]]

    distances = [r["distance"] for r in body["results"]]
    assert distances == sorted(distances), "pgvector must return ascending cosine distance"
    for r in body["results"]:
        assert abs(r["similarity"] - (1.0 - r["distance"])) < 1e-6


def test_similar_needs_an_embedding(client, auth):
    item = client.post(
        "/api/v1/wardrobe/items", json={"name": "no image"}, headers=auth
    ).get_json()["item"]
    resp = client.get(f"/api/v1/wardrobe/items/{item['id']}/similar", headers=auth)
    assert resp.status_code == 422


def test_search_ranks_by_clip_text_similarity(client, auth, make_item):
    for i in range(5):
        make_item(name=f"item{i}")

    body = client.post(
        "/api/v1/wardrobe/search", json={"query": "something warm", "k": 3}, headers=auth
    ).get_json()
    assert body["query"] == "something warm"
    assert len(body["results"]) == 3
    assert [r["distance"] for r in body["results"]] == sorted(
        r["distance"] for r in body["results"]
    )
    assert body["timings_ms"]["clip"] >= 0
    assert body["timings_ms"]["retrieval"] >= 0


def test_search_can_exclude_dirty_items(client, auth, make_item):
    make_item(name="clean")
    make_item(name="dirty", dirty="true")
    body = client.post(
        "/api/v1/wardrobe/search",
        json={"query": "anything", "include_dirty": False},
        headers=auth,
    ).get_json()
    assert [r["name"] for r in body["results"]] == ["clean"]


def test_search_requires_a_query(client, auth):
    assert client.post("/api/v1/wardrobe/search", json={}, headers=auth).status_code == 422


def test_search_only_returns_the_callers_items(client, auth, other_auth, make_item):
    make_item(name="mine")
    body = client.post(
        "/api/v1/wardrobe/search", json={"query": "anything"}, headers=other_auth
    ).get_json()
    assert body["results"] == []


def test_reembed_lists_items_missing_vectors(client, auth, make_item):
    make_item(name="has embedding")
    client.post("/api/v1/wardrobe/items", json={"name": "no embedding"}, headers=auth)
    body = client.post("/api/v1/wardrobe/reembed", json={}, headers=auth).get_json()
    assert body["count"] == 1
    assert body["missing_embeddings"][0]["name"] == "no embedding"
