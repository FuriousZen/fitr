"""Liveness and readiness."""

from __future__ import annotations

from flask import Blueprint, current_app
from sqlalchemy import text

from ..extensions import db
from ..services import services

bp = Blueprint("health", __name__)


def _db_status() -> dict:
    try:
        db.session.execute(text("SELECT 1"))
        version = db.session.execute(
            text("SELECT extversion FROM pg_extension WHERE extname = 'vector'")
        ).scalar()
        return {"connected": True, "pgvector": version}
    except Exception as exc:  # pragma: no cover - only on a broken database
        return {"connected": False, "error": str(exc)[:200]}


@bp.get("/healthz")
def healthz():
    """Cheap liveness probe. Does not touch CLIP or any third party."""
    db_status = _db_status()
    ok = bool(db_status.get("connected"))
    return {"status": "ok" if ok else "degraded", "database": db_status}, (
        200 if ok else 503
    )


@bp.get("/api/v1/health")
def health_detail():
    """Full readiness report, including which third-party keys are configured."""
    svc = services()
    db_status = _db_status()
    return {
        "status": "ok" if db_status.get("connected") else "degraded",
        "database": db_status,
        "clip": svc.encoder.health(),
        "embedding_cache": svc.cache.health(),
        "weather": svc.weather.health(),
        "gemini": svc.gemini.health(),
        "config": {
            "auth_mode": current_app.config["AUTH_MODE"],
            "candidate_k": current_app.config["CANDIDATE_K"],
            "embed_dim": current_app.config["EMBED_DIM"],
        },
    }
