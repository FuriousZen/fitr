"""Measured metrics.

Both endpoints report only what has actually been recorded in this database.
When there is no data they return ``null`` rather than a placeholder number —
an unmeasured rate must never be indistinguishable from a measured one.
"""

from __future__ import annotations

from flask import Blueprint, request
from sqlalchemy import func, select

from ..auth import require_user
from ..extensions import db
from ..models import Recommendation, RecommendationFeedback
from .helpers import get_int, get_str

bp = Blueprint("metrics", __name__, url_prefix="/api/v1/metrics")


def _percentile(values: list[float], pct: float) -> float | None:
    """Nearest-rank percentile. No interpolation, so every reported number is
    an observation that actually happened."""
    if not values:
        return None
    ordered = sorted(values)
    rank = max(1, int(round(pct / 100.0 * len(ordered))))
    return round(ordered[min(rank, len(ordered)) - 1], 2)


@bp.get("/acceptance")
@require_user
def acceptance():
    """Top-k recommendation acceptance, computed from submitted feedback.

    top_k_acceptance = (feedback rows with accepted=true and accepted_rank<=k)
                       / (all feedback rows)

    This is null until real users submit feedback. There is no seeded or
    simulated feedback anywhere in this repository.
    """
    top_k = get_int(request.args.to_dict(flat=True), "top_k", 3, minimum=1, maximum=50)

    total_recommendations = db.session.execute(
        select(func.count()).select_from(Recommendation)
    ).scalar_one()
    with_feedback = db.session.execute(
        select(func.count()).select_from(RecommendationFeedback)
    ).scalar_one()
    accepted_in_top_k = db.session.execute(
        select(func.count())
        .select_from(RecommendationFeedback)
        .where(
            RecommendationFeedback.accepted.is_(True),
            RecommendationFeedback.accepted_rank.isnot(None),
            RecommendationFeedback.accepted_rank <= top_k,
        )
    ).scalar_one()
    distinct_users = db.session.execute(
        select(func.count(func.distinct(RecommendationFeedback.user_id)))
    ).scalar_one()

    rate = round(accepted_in_top_k / with_feedback, 4) if with_feedback else None

    return {
        "top_k": top_k,
        "total_recommendations": int(total_recommendations),
        "recommendations_with_feedback": int(with_feedback),
        "accepted_within_top_k": int(accepted_in_top_k),
        "top_k_acceptance": rate,
        "distinct_users_with_feedback": int(distinct_users),
        "note": (
            "null acceptance means no feedback has been submitted. This value is "
            "computed only from rows in recommendation_feedback."
        )
        if rate is None
        else None,
    }


@bp.get("/latency")
@require_user
def latency():
    """Latency percentiles over stored recommendations.

    Optional ``generator`` filter (``gemini`` / ``heuristic``) matters a great
    deal: the heuristic path makes no network call, so mixing the two produces
    a meaningless median.
    """
    args = request.args.to_dict(flat=True)
    generator = get_str(args, "generator")
    limit = get_int(args, "limit", 1000, minimum=1, maximum=100_000)

    stmt = select(
        Recommendation.total_ms,
        Recommendation.weather_ms,
        Recommendation.clip_ms,
        Recommendation.retrieval_ms,
        Recommendation.generation_ms,
    ).order_by(Recommendation.created_at.desc())
    if generator:
        stmt = stmt.where(Recommendation.generator == generator)
    rows = db.session.execute(stmt.limit(limit)).all()

    if not rows:
        return {
            "samples": 0,
            "generator": generator or "all",
            "total_ms": None,
            "note": "no recommendations recorded yet",
        }

    def column(idx: int) -> list[float]:
        return [float(r[idx]) for r in rows]

    def summary(values: list[float]) -> dict:
        return {
            "p50": _percentile(values, 50),
            "p90": _percentile(values, 90),
            "p95": _percentile(values, 95),
            "max": round(max(values), 2),
        }

    return {
        "samples": len(rows),
        "generator": generator or "all",
        "total_ms": summary(column(0)),
        "breakdown_ms": {
            "weather": summary(column(1)),
            "clip": summary(column(2)),
            "retrieval": summary(column(3)),
            "generation": summary(column(4)),
        },
    }


@bp.get("/cache")
@require_user
def cache_metrics():
    from ..models import ImageEmbedding
    from ..services import services

    rows = db.session.execute(
        select(
            func.count(),
            func.coalesce(func.sum(ImageEmbedding.hit_count), 0),
            func.avg(ImageEmbedding.compute_ms),
        ).select_from(ImageEmbedding)
    ).one()

    return {
        "process_cache": services().cache.health(),
        "postgres_cache": {
            "rows": int(rows[0]),
            "total_l2_hits": int(rows[1]),
            "mean_cold_compute_ms": round(float(rows[2]), 2) if rows[2] is not None else None,
        },
    }
