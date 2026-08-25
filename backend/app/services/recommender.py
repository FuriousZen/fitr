"""End-to-end outfit recommendation.

    weather  ->  CLIP text query  ->  pgvector k-NN shortlist  ->  Gemini  ->  ranked outfits

CLIP does the retrieval work here: the shortlist that reaches the LLM is
chosen by cosine similarity between a CLIP *text* embedding of the situation
("a casual outfit for cool rainy weather") and the CLIP *image* embeddings of
the user's own garments. That keeps the prompt at a fixed size no matter how
large the wardrobe grows, which is what keeps generation latency flat.

If Gemini is unconfigured or errors, ``_heuristic_options`` still returns a
ranked answer built from the CLIP ordering plus the weather rules. The endpoint
never fails just because a third-party key is missing; the ``generator`` field
in the response says which path ran.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field

from sqlalchemy import select

from ..extensions import db
from ..models import ClothingItem
from .clip import ClipEncoder
from .gemini import GeminiService, GeminiUnavailableError

log = logging.getLogger(__name__)

TOP_TYPES = {"T-Shirt", "Shirt", "Sweater"}
BOTTOM_TYPES = {"Jeans", "Pants", "Shorts", "Skirt"}
OUTER_TYPES = {"Jacket", "Coat"}
ONE_PIECE_TYPES = {"Dress"}
SHOE_TYPES = {"Shoes"}


@dataclass
class RecommendationOutcome:
    options: list[dict]
    candidates: list[dict]
    query_text: str
    generator: str
    model: str | None
    weather: dict
    timings: dict = field(default_factory=dict)


def temperature_band(temp: float, units: str) -> str:
    """Bucket a temperature into a ``WeatherTag``-compatible band."""
    celsius = temp
    if units == "imperial":
        celsius = (temp - 32.0) * 5.0 / 9.0
    elif units == "standard":
        celsius = temp - 273.15
    if celsius >= 25.0:
        return "Hot"
    if celsius >= 18.0:
        return "Warm"
    if celsius >= 10.0:
        return "Cool"
    return "Cold"


def build_query_text(vibe: str, weather: dict) -> str:
    """The natural-language situation description handed to CLIP's text tower."""
    condition = (weather.get("condition") or "Cloudy").lower()
    band = temperature_band(
        float(weather.get("temperature", 60.0)), weather.get("units", "imperial")
    ).lower()
    vibe_part = (vibe or "everyday").strip().lower()
    return (
        f"a photo of a {vibe_part} outfit to wear in {band} {condition} weather"
    )


class Recommender:
    def __init__(
        self,
        encoder: ClipEncoder,
        gemini: GeminiService,
        candidate_k: int = 12,
    ) -> None:
        self.encoder = encoder
        self.gemini = gemini
        self.candidate_k = candidate_k

    # -- retrieval ---------------------------------------------------------

    def shortlist(
        self, user_id: str, query_vec, k: int, include_dirty: bool = False
    ) -> list[tuple[ClothingItem, float]]:
        """pgvector cosine k-NN over one user's items.

        Ordering happens in Postgres via the ``<=>`` operator so the HNSW index
        can be used; nothing is ranked in Python.
        """
        stmt = select(
            ClothingItem,
            ClothingItem.embedding.cosine_distance(query_vec).label("distance"),
        ).where(
            ClothingItem.user_id == user_id,
            ClothingItem.embedding.isnot(None),
        )
        if not include_dirty:
            stmt = stmt.where(ClothingItem.dirty.is_(False))
        stmt = stmt.order_by("distance").limit(k)
        rows = db.session.execute(stmt).all()
        return [(row[0], float(row[1])) for row in rows]

    # -- fallback ----------------------------------------------------------

    @staticmethod
    def _heuristic_options(candidates: list[dict], weather: dict, num_options: int) -> list[dict]:
        """Rank-aware outfit assembly with no LLM in the loop.

        Walks the CLIP-ordered candidate list and greedily fills slots, seeding
        each successive option from a different top so the options differ.
        """
        band = temperature_band(
            float(weather.get("temperature", 60.0)), weather.get("units", "imperial")
        )
        condition = weather.get("condition", "Cloudy")
        needs_layer = band == "Cold"
        wet = condition in {"Rainy", "Snowy", "Stormy"}

        # candidates arrive in CLIP-similarity order; carry that order as an
        # explicit key rather than relying on list.index (which compares dicts
        # by value and would tie-break wrongly on duplicate rows).
        order = {id(c): i for i, c in enumerate(candidates)}
        by_type: dict[str, list[dict]] = {}
        for c in candidates:
            by_type.setdefault(c.get("type", "Other"), []).append(c)

        def pool(types: set[str]) -> list[dict]:
            out: list[dict] = []
            for t in types:
                out.extend(by_type.get(t, []))
            return sorted(out, key=lambda c: order[id(c)])

        tops = pool(TOP_TYPES)
        bottoms = pool(BOTTOM_TYPES)
        outers = pool(OUTER_TYPES)
        dresses = pool(ONE_PIECE_TYPES)
        shoes = pool(SHOE_TYPES)

        options: list[dict] = []
        seen: set[tuple[str, ...]] = set()

        def emit(items: list[dict]) -> None:
            if not items:
                return
            ids = tuple(sorted(i["id"] for i in items))
            if ids in seen:
                return
            seen.add(ids)
            names = ", ".join(f"{i.get('color','')} {i.get('type','')}".strip() for i in items)
            note = " Bring a layer, it's cold." if needs_layer else ""
            note += " Water-resistant picks for the wet weather." if wet else ""
            options.append(
                {
                    "rank": len(options) + 1,
                    "item_ids": [i["id"] for i in items],
                    "description": f"{names}.{note}".strip(),
                }
            )

        for idx in range(num_options):
            items: list[dict] = []
            if idx < len(dresses) and not tops:
                items.append(dresses[idx])
            else:
                if idx < len(tops):
                    items.append(tops[idx])
                elif tops:
                    items.append(tops[idx % len(tops)])
                if bottoms:
                    items.append(bottoms[min(idx, len(bottoms) - 1)])
            if (needs_layer or wet) and outers:
                items.append(outers[min(idx, len(outers) - 1)])
            if shoes:
                items.append(shoes[min(idx, len(shoes) - 1)])
            # An "outfit" of a single garment is not an outfit.
            if len(items) >= 2:
                emit(items)

        return options[:num_options]

    # -- orchestration -----------------------------------------------------

    def recommend(
        self,
        user_id: str,
        vibe: str,
        weather: dict,
        num_options: int = 3,
        candidate_k: int | None = None,
        include_dirty: bool = False,
    ) -> RecommendationOutcome:
        k = candidate_k or self.candidate_k
        timings: dict[str, float] = {}

        query_text = build_query_text(vibe, weather)

        started = time.perf_counter()
        # Cached: query text is drawn from vibe x temperature band x condition,
        # a space small enough that repeat requests almost always hit.
        query_vec = self.encoder.encode_text_cached(query_text)
        timings["clip"] = (time.perf_counter() - started) * 1000.0

        started = time.perf_counter()
        ranked = self.shortlist(user_id, query_vec.tolist(), k, include_dirty=include_dirty)
        timings["retrieval"] = (time.perf_counter() - started) * 1000.0

        candidates = []
        for item, distance in ranked:
            payload = item.to_dict()
            payload["clip_distance"] = round(distance, 6)
            payload["clip_similarity"] = round(1.0 - distance, 6)
            candidates.append(payload)

        if not candidates:
            return RecommendationOutcome(
                options=[],
                candidates=[],
                query_text=query_text,
                generator="none",
                model=None,
                weather=weather,
                timings=timings | {"generation": 0.0},
            )

        generator = "heuristic"
        model = None
        options: list[dict] = []
        started = time.perf_counter()
        if self.gemini.configured:
            try:
                result = self.gemini.generate_outfits(
                    vibe=vibe, weather=weather, candidates=candidates, num_options=num_options
                )
                options = result.options
                model = result.model
                generator = "gemini"
            except GeminiUnavailableError as exc:
                log.warning("Gemini generation failed, falling back to heuristic: %s", exc)
        if not options:
            options = self._heuristic_options(candidates, weather, num_options)
            if generator == "gemini":
                generator = "gemini_empty_fallback"
            else:
                generator = "heuristic"
            model = model or None
        timings["generation"] = (time.perf_counter() - started) * 1000.0

        return RecommendationOutcome(
            options=options,
            candidates=candidates,
            query_text=query_text,
            generator=generator,
            model=model,
            weather=weather,
            timings=timings,
        )
