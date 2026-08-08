"""Clothing taxonomy — kept byte-identical to the Swift enums.

Mirrors ``fitr/Models/ClothingItem.swift`` (``ClothingType``, ``WeatherTag``,
``StyleTag``) and ``fitr/Models/Weather.swift`` (``WeatherCondition``). The raw
string values are the wire format on both sides, so these lists must not drift
from the Swift source.
"""

from __future__ import annotations

CLOTHING_TYPES: tuple[str, ...] = (
    "T-Shirt",
    "Shirt",
    "Sweater",
    "Jacket",
    "Coat",
    "Jeans",
    "Pants",
    "Shorts",
    "Skirt",
    "Dress",
    "Shoes",
    "Accessory",
    "Other",
)

WEATHER_TAGS: tuple[str, ...] = (
    "Hot",
    "Warm",
    "Cool",
    "Cold",
    "Rainy",
    "Snowy",
    "Windy",
)

STYLE_TAGS: tuple[str, ...] = (
    "casual",
    "formal",
    "business",
    "elegant",
    "athletic",
    "sporty",
    "comfortable",
    "trendy",
    "stylish",
    "everyday",
    "warm",
)

WEATHER_CONDITIONS: tuple[str, ...] = (
    "Sunny",
    "Cloudy",
    "Rainy",
    "Snowy",
    "Stormy",
    "Windy",
    "Foggy",
)

#: Colours used only for CLIP zero-shot colour scoring; not a Swift enum.
COLORS: tuple[str, ...] = (
    "black",
    "white",
    "grey",
    "navy",
    "blue",
    "light blue",
    "red",
    "pink",
    "orange",
    "yellow",
    "green",
    "olive",
    "brown",
    "beige",
    "cream",
    "purple",
    "multicolored",
)

#: CLIP is sensitive to prompt phrasing; the "a photo of ..." template is the
#: one used in the original CLIP paper's zero-shot ImageNet evaluation.
TYPE_PROMPT = "a photo of a {label}, an item of clothing"
COLOR_PROMPT = "a photo of a {label} colored piece of clothing"
STYLE_PROMPT = "a photo of a {label} style outfit item"
WEATHER_PROMPT = "a photo of clothing suitable for {label} weather"


def _lower(values: tuple[str, ...]) -> tuple[str, ...]:
    return tuple(v.lower() for v in values)


CLOTHING_TYPES_LOWER = _lower(CLOTHING_TYPES)
WEATHER_TAGS_LOWER = _lower(WEATHER_TAGS)
STYLE_TAGS_LOWER = _lower(STYLE_TAGS)


def canonical_type(value: str | None) -> str:
    """Map a free-form type string onto the Swift ``ClothingType`` raw value."""
    if not value:
        return "Other"
    lowered = value.strip().lower()
    for canonical in CLOTHING_TYPES:
        if canonical.lower() == lowered:
            return canonical
    return "Other"


def canonical_weather_tags(values: list[str] | None) -> list[str]:
    if not values:
        return []
    lookup = {c.lower(): c for c in WEATHER_TAGS}
    out: list[str] = []
    for v in values:
        c = lookup.get(str(v).strip().lower())
        if c and c not in out:
            out.append(c)
    return out


def canonical_style_tags(values: list[str] | None) -> list[str]:
    if not values:
        return []
    lookup = {c.lower(): c for c in STYLE_TAGS}
    out: list[str] = []
    for v in values:
        c = lookup.get(str(v).strip().lower())
        if c and c not in out:
            out.append(c)
    return out
