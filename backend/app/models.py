"""SQLAlchemy 2.0 models.

Two tables hold vectors, deliberately:

``image_embeddings``
    The *cache*. Content-addressed by SHA-256 of the raw image bytes and keyed
    additionally by model id, so re-uploading identical bytes — or a second user
    uploading the same stock photo — never re-runs CLIP. Global, not per-user.

``clothing_items.embedding``
    A denormalised copy of the same vector on the row that is actually searched,
    so the HNSW index can serve per-user k-NN without a join. The duplication is
    intentional and is the reason repeat requests are cheap.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from pgvector.sqlalchemy import VECTOR
from sqlalchemy import (
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import ARRAY, JSONB
from sqlalchemy.orm import Mapped, mapped_column

from .config import Config
from .extensions import db

EMBED_DIM = Config.EMBED_DIM


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _uuid() -> str:
    return str(uuid.uuid4())


class ImageEmbedding(db.Model):
    """Content-addressed CLIP embedding cache (the L2 tier)."""

    __tablename__ = "image_embeddings"

    content_hash: Mapped[str] = mapped_column(String(64), primary_key=True)
    model_id: Mapped[str] = mapped_column(String(128), primary_key=True)
    dim: Mapped[int] = mapped_column(Integer, nullable=False)
    embedding: Mapped[list[float]] = mapped_column(VECTOR(EMBED_DIM), nullable=False)
    #: Wall-clock cost of the CLIP forward pass that produced this row. Kept so
    #: `scripts/benchmark.py` can report a real, non-synthetic cold cost.
    compute_ms: Mapped[float | None] = mapped_column(Float, nullable=True)
    hit_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow
    )

    def to_dict(self) -> dict:
        return {
            "content_hash": self.content_hash,
            "model_id": self.model_id,
            "dim": self.dim,
            "hit_count": self.hit_count,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }


class ClothingItem(db.Model):
    """A wardrobe item. Mirrors the Swift ``ClothingItem`` struct."""

    __tablename__ = "clothing_items"

    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(String(128), nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False, default="")
    type: Mapped[str] = mapped_column(String(40), nullable=False, default="Other")
    color: Mapped[str] = mapped_column(String(60), nullable=False, default="")
    image_url: Mapped[str] = mapped_column(Text, nullable=False, default="")
    weather_tags: Mapped[list[str]] = mapped_column(
        ARRAY(String), nullable=False, default=list
    )
    style_tags: Mapped[list[str]] = mapped_column(
        ARRAY(String), nullable=False, default=list
    )
    dirty: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    content_hash: Mapped[str | None] = mapped_column(String(64), nullable=True)
    embedding: Mapped[list[float] | None] = mapped_column(
        VECTOR(EMBED_DIM), nullable=True
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow
    )

    __table_args__ = (
        Index("ix_clothing_items_user_dirty", "user_id", "dirty"),
        # Cosine index. Vectors are L2-normalised at write time, so cosine
        # distance and (1 - dot product) coincide; cosine_ops is still the
        # correct opclass because the column type does not enforce normality.
        Index(
            "ix_clothing_items_embedding_hnsw",
            "embedding",
            postgresql_using="hnsw",
            postgresql_with={"m": 16, "ef_construction": 64},
            postgresql_ops={"embedding": "vector_cosine_ops"},
        ),
    )

    def to_dict(self, include_embedding: bool = False) -> dict:
        out = {
            "id": self.id,
            "user_id": self.user_id,
            "name": self.name,
            "type": self.type,
            "color": self.color,
            "image_url": self.image_url,
            "weather_tags": list(self.weather_tags or []),
            "style_tags": list(self.style_tags or []),
            "dirty": self.dirty,
            "content_hash": self.content_hash,
            "has_embedding": self.embedding is not None,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
        if include_embedding and self.embedding is not None:
            out["embedding"] = [float(x) for x in self.embedding]
        return out


class Recommendation(db.Model):
    """One generated recommendation request and its ranked options.

    ``options`` is a list of ``{"rank": int, "item_ids": [...], "description": str}``.
    Storing the full ranked list (not just the winner) is what makes a *top-k*
    acceptance metric computable later.
    """

    __tablename__ = "recommendations"

    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(String(128), nullable=False, index=True)
    vibe: Mapped[str] = mapped_column(String(80), nullable=False, default="")
    weather: Mapped[dict] = mapped_column(JSONB, nullable=False, default=dict)
    query_text: Mapped[str] = mapped_column(Text, nullable=False, default="")
    candidate_item_ids: Mapped[list[str]] = mapped_column(
        ARRAY(String), nullable=False, default=list
    )
    options: Mapped[list] = mapped_column(JSONB, nullable=False, default=list)

    #: "gemini" when the LLM produced the ranking, "heuristic" when the
    #: CLIP-only fallback did (no API key, or the call failed).
    generator: Mapped[str] = mapped_column(String(40), nullable=False, default="heuristic")
    model: Mapped[str | None] = mapped_column(String(120), nullable=True)

    total_ms: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    weather_ms: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    clip_ms: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    retrieval_ms: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    generation_ms: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    embedding_cache_tier: Mapped[str | None] = mapped_column(String(16), nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow, index=True
    )

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "user_id": self.user_id,
            "vibe": self.vibe,
            "weather": self.weather,
            "query_text": self.query_text,
            "candidate_item_ids": list(self.candidate_item_ids or []),
            "options": self.options or [],
            "generator": self.generator,
            "model": self.model,
            "timings_ms": {
                "total": round(self.total_ms, 2),
                "weather": round(self.weather_ms, 2),
                "clip": round(self.clip_ms, 2),
                "retrieval": round(self.retrieval_ms, 2),
                "generation": round(self.generation_ms, 2),
            },
            "embedding_cache_tier": self.embedding_cache_tier,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }


class RecommendationFeedback(db.Model):
    """Acceptance instrumentation.

    This table is the mechanism by which a "top-k acceptance rate" *could* be
    measured from a real user cohort. It is empty unless clients POST to
    ``/api/v1/recommendations/<id>/feedback``. Nothing in this repo populates it
    with synthetic data.
    """

    __tablename__ = "recommendation_feedback"

    id: Mapped[str] = mapped_column(String(64), primary_key=True, default=_uuid)
    recommendation_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("recommendations.id", ondelete="CASCADE"), nullable=False
    )
    user_id: Mapped[str] = mapped_column(String(128), nullable=False, index=True)
    accepted: Mapped[bool] = mapped_column(Boolean, nullable=False)
    #: 1-based rank of the option the user actually wore. NULL when nothing was
    #: accepted. A value of 1..3 with accepted=True is a "top-3 acceptance".
    accepted_rank: Mapped[int | None] = mapped_column(Integer, nullable=True)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow
    )

    __table_args__ = (
        UniqueConstraint("recommendation_id", name="uq_feedback_per_recommendation"),
    )

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "recommendation_id": self.recommendation_id,
            "user_id": self.user_id,
            "accepted": self.accepted,
            "accepted_rank": self.accepted_rank,
            "note": self.note,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
