"""Wardrobe CRUD plus vector search."""

from __future__ import annotations

import time

from flask import Blueprint, current_app, request
from sqlalchemy import select

from ..auth import current_user_id, require_user
from ..errors import NotFound, ServiceUnavailable, ValidationError
from ..extensions import db
from ..models import ClothingItem
from ..services import services
from ..services.clip import ClipUnavailableError
from ..taxonomy import canonical_style_tags, canonical_type, canonical_weather_tags
from .helpers import (
    form_or_json,
    get_bool,
    get_int,
    get_str,
    get_str_list,
    read_image_bytes,
)

bp = Blueprint("wardrobe", __name__, url_prefix="/api/v1/wardrobe")


def _load_item(item_id: str, user_id: str) -> ClothingItem:
    item = db.session.get(ClothingItem, item_id)
    if item is None or item.user_id != user_id:
        # Deliberately identical for "absent" and "someone else's" so the API
        # is not an existence oracle for other users' item ids.
        raise NotFound(f"clothing item {item_id!r} not found")
    return item


@bp.post("/items")
@require_user
def create_item():
    """Create a wardrobe item, embedding its photo through the CLIP cache.

    multipart/form-data with an ``image`` part, or JSON with ``image_base64``.
    The image is optional; without one the item is stored without an embedding
    and will not appear in vector search.
    """
    user_id = current_user_id()
    data = form_or_json()
    svc = services()

    image_bytes = read_image_bytes(required=False)
    embedding = None
    content_hash = None
    cache_tier = None
    embed_ms = 0.0

    if image_bytes:
        try:
            cached = svc.cache.get_or_compute(image_bytes)
        except ClipUnavailableError as exc:
            raise ServiceUnavailable(str(exc)) from exc
        embedding = cached.vector.tolist()
        content_hash = cached.content_hash
        cache_tier = cached.tier
        embed_ms = cached.elapsed_ms

    item = ClothingItem(
        user_id=user_id,
        name=get_str(data, "name"),
        type=canonical_type(get_str(data, "type")),
        color=get_str(data, "color"),
        image_url=get_str(data, "image_url"),
        weather_tags=canonical_weather_tags(get_str_list(data, "weather_tags")),
        style_tags=canonical_style_tags(get_str_list(data, "style_tags")),
        dirty=get_bool(data, "dirty", False),
        content_hash=content_hash,
        embedding=embedding,
    )
    if "id" in data and get_str(data, "id"):
        # Lets the iOS client keep the Firestore document id as the primary key
        # so the two stores stay addressable by the same identifier.
        item.id = get_str(data, "id")

    db.session.add(item)
    db.session.commit()

    return {
        "item": item.to_dict(),
        "embedding_cache_tier": cache_tier,
        "embedding_ms": round(embed_ms, 2),
    }, 201


@bp.get("/items")
@require_user
def list_items():
    user_id = current_user_id()
    args = request.args.to_dict(flat=True)
    limit = get_int(args, "limit", 100, minimum=1, maximum=500)
    offset = get_int(args, "offset", 0, minimum=0, maximum=1_000_000)

    stmt = select(ClothingItem).where(ClothingItem.user_id == user_id)
    if "dirty" in args:
        stmt = stmt.where(ClothingItem.dirty.is_(get_bool(args, "dirty")))
    if "type" in args:
        stmt = stmt.where(ClothingItem.type == canonical_type(args["type"]))
    stmt = stmt.order_by(ClothingItem.created_at.desc()).limit(limit).offset(offset)

    items = db.session.execute(stmt).scalars().all()
    return {"items": [i.to_dict() for i in items], "count": len(items)}


@bp.get("/items/<item_id>")
@require_user
def get_item(item_id: str):
    item = _load_item(item_id, current_user_id())
    include = get_bool(request.args.to_dict(flat=True), "include_embedding", False)
    return {"item": item.to_dict(include_embedding=include)}


@bp.patch("/items/<item_id>")
@require_user
def update_item(item_id: str):
    item = _load_item(item_id, current_user_id())
    data = form_or_json()

    if "name" in data:
        item.name = get_str(data, "name")
    if "color" in data:
        item.color = get_str(data, "color")
    if "type" in data:
        item.type = canonical_type(get_str(data, "type"))
    if "image_url" in data:
        item.image_url = get_str(data, "image_url")
    if "dirty" in data:
        item.dirty = get_bool(data, "dirty")
    if "weather_tags" in data:
        item.weather_tags = canonical_weather_tags(get_str_list(data, "weather_tags"))
    if "style_tags" in data:
        item.style_tags = canonical_style_tags(get_str_list(data, "style_tags"))

    db.session.commit()
    return {"item": item.to_dict()}


@bp.delete("/items/<item_id>")
@require_user
def delete_item(item_id: str):
    item = _load_item(item_id, current_user_id())
    db.session.delete(item)
    db.session.commit()
    # The cached embedding is intentionally NOT deleted: it is content-addressed
    # and shared, so another item (or user) may still need it.
    return {"deleted": item_id}


@bp.post("/wash")
@require_user
def wash_items():
    """Mark items clean in bulk — the backend counterpart to the laundry view."""
    user_id = current_user_id()
    data = form_or_json()
    item_ids = get_str_list(data, "item_ids")
    if not item_ids:
        raise ValidationError("item_ids is required")

    stmt = select(ClothingItem).where(
        ClothingItem.user_id == user_id, ClothingItem.id.in_(item_ids)
    )
    items = db.session.execute(stmt).scalars().all()
    for item in items:
        item.dirty = False
    db.session.commit()
    return {"washed": [i.id for i in items], "count": len(items)}


@bp.get("/items/<item_id>/similar")
@require_user
def similar_items(item_id: str):
    """k-NN over the caller's wardrobe, ordered by pgvector cosine distance."""
    user_id = current_user_id()
    item = _load_item(item_id, user_id)
    if item.embedding is None:
        raise ValidationError(f"item {item_id!r} has no embedding to compare against")

    args = request.args.to_dict(flat=True)
    k = get_int(args, "k", 5, minimum=1, maximum=100)

    stmt = (
        select(
            ClothingItem,
            ClothingItem.embedding.cosine_distance(item.embedding).label("distance"),
        )
        .where(
            ClothingItem.user_id == user_id,
            ClothingItem.id != item.id,
            ClothingItem.embedding.isnot(None),
        )
        .order_by("distance")
        .limit(k)
    )
    rows = db.session.execute(stmt).all()
    return {
        "query_item_id": item.id,
        "results": [
            {
                **row[0].to_dict(),
                "distance": round(float(row[1]), 6),
                "similarity": round(1.0 - float(row[1]), 6),
            }
            for row in rows
        ],
    }


@bp.post("/search")
@require_user
def search_items():
    """Natural-language wardrobe search: CLIP text tower -> pgvector k-NN."""
    user_id = current_user_id()
    data = form_or_json()
    query = get_str(data, "query", required=True)
    k = get_int(data, "k", 10, minimum=1, maximum=100)
    include_dirty = get_bool(data, "include_dirty", True)
    svc = services()

    started = time.perf_counter()
    try:
        query_vec = svc.encoder.encode_text(query)
    except ClipUnavailableError as exc:
        raise ServiceUnavailable(str(exc)) from exc
    clip_ms = (time.perf_counter() - started) * 1000.0

    started = time.perf_counter()
    stmt = select(
        ClothingItem,
        ClothingItem.embedding.cosine_distance(query_vec.tolist()).label("distance"),
    ).where(ClothingItem.user_id == user_id, ClothingItem.embedding.isnot(None))
    if not include_dirty:
        stmt = stmt.where(ClothingItem.dirty.is_(False))
    rows = db.session.execute(stmt.order_by("distance").limit(k)).all()
    retrieval_ms = (time.perf_counter() - started) * 1000.0

    return {
        "query": query,
        "results": [
            {
                **row[0].to_dict(),
                "distance": round(float(row[1]), 6),
                "similarity": round(1.0 - float(row[1]), 6),
            }
            for row in rows
        ],
        "timings_ms": {
            "clip": round(clip_ms, 2),
            "retrieval": round(retrieval_ms, 2),
        },
    }


@bp.post("/reembed")
@require_user
def reembed():
    """Backfill embeddings for items that have an image_url but no vector.

    Only useful when items were created without an image part; it does not
    fetch remote URLs (the backend has no credentials for Firebase Storage).
    Reports what is missing so a client can re-upload.
    """
    user_id = current_user_id()
    stmt = select(ClothingItem).where(
        ClothingItem.user_id == user_id, ClothingItem.embedding.is_(None)
    )
    missing = db.session.execute(stmt).scalars().all()
    return {
        "missing_embeddings": [
            {"id": i.id, "name": i.name, "image_url": i.image_url} for i in missing
        ],
        "count": len(missing),
        "hint": "re-POST each item's image to /api/v1/wardrobe/items or PATCH with an image",
    }
