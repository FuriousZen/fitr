from __future__ import annotations

import numpy as np
import pytest

from app.services.vision import ZeroShotClassifier, _softmax
from app.taxonomy import (
    CLOTHING_TYPES,
    STYLE_TAGS,
    WEATHER_TAGS,
    canonical_style_tags,
    canonical_type,
    canonical_weather_tags,
)


@pytest.mark.parametrize(
    "raw,expected",
    [
        ("T-Shirt", "T-Shirt"),
        ("t-shirt", "T-Shirt"),
        ("  JEANS  ", "Jeans"),
        ("Sweater", "Sweater"),
        ("spacesuit", "Other"),
        ("", "Other"),
        (None, "Other"),
    ],
)
def test_canonical_type(raw, expected):
    assert canonical_type(raw) == expected


def test_canonical_weather_tags_filters_and_dedupes():
    assert canonical_weather_tags(["hot", "HOT", "Cold", "volcanic"]) == ["Hot", "Cold"]
    assert canonical_weather_tags(None) == []
    assert canonical_weather_tags([]) == []


def test_canonical_style_tags_filters_and_dedupes():
    assert canonical_style_tags(["Casual", "casual", "goth"]) == ["casual"]


def test_taxonomy_matches_the_swift_enums():
    """These raw values are the wire format shared with the iOS app; drift here
    silently breaks decoding on the client."""
    assert CLOTHING_TYPES[0] == "T-Shirt"
    assert "Accessory" in CLOTHING_TYPES and "Other" in CLOTHING_TYPES
    assert len(CLOTHING_TYPES) == 13
    assert WEATHER_TAGS == ("Hot", "Warm", "Cool", "Cold", "Rainy", "Snowy", "Windy")
    assert len(STYLE_TAGS) == 11
    assert STYLE_TAGS[0] == "casual"


def test_softmax_is_a_distribution():
    out = _softmax(np.array([1.0, 2.0, 3.0]))
    assert abs(float(out.sum()) - 1.0) < 1e-6
    assert out[2] > out[1] > out[0]


def test_softmax_is_numerically_stable():
    out = _softmax(np.array([1000.0, 1001.0]))
    assert np.isfinite(out).all()
    assert abs(float(out.sum()) - 1.0) < 1e-6


def test_classifier_output_shape_with_a_fake_encoder(app, services):
    vec = np.zeros(512, dtype=np.float32)
    vec[0] = 1.0
    result = ZeroShotClassifier(services.encoder).classify(vec)

    assert result["type"] in CLOTHING_TYPES
    assert result["weather_tags"] and set(result["weather_tags"]) <= set(WEATHER_TAGS)
    assert result["style_tags"] and set(result["style_tags"]) <= set(STYLE_TAGS)
    for head in ("type", "color", "style", "weather"):
        scores = [s["score"] for s in result["scores"][head]]
        assert scores == sorted(scores, reverse=True)


def test_classify_endpoint_returns_a_taxonomy_label(client, auth, upload):
    from .conftest import make_image

    body = client.post(
        "/api/v1/vision/classify",
        data=upload(make_image(label="classify")),
        headers=auth,
        content_type="multipart/form-data",
    ).get_json()

    assert body["type"] in CLOTHING_TYPES
    assert body["cache_tier"] == "miss"
    assert body["content_hash"]


def test_classify_reuses_the_embedding_cache(client, auth, upload, services):
    from .conftest import make_image

    image = make_image(label="reuse")
    client.post(
        "/api/v1/embeddings",
        data=upload(image),
        headers=auth,
        content_type="multipart/form-data",
    )
    body = client.post(
        "/api/v1/vision/classify",
        data=upload(image),
        headers=auth,
        content_type="multipart/form-data",
    ).get_json()

    assert body["cache_tier"] == "l1"
    assert services.encoder.image_calls == 1, "classification must not re-embed"


def test_label_prompts_are_encoded_once_and_memoized(app, services):
    vec = np.zeros(512, dtype=np.float32)
    vec[0] = 1.0
    classifier = ZeroShotClassifier(services.encoder)

    classifier.classify(vec)
    calls_after_first = services.encoder.text_calls
    classifier.classify(vec)

    assert services.encoder.text_calls == calls_after_first, (
        "the fixed label vocabulary must not be re-encoded per request"
    )
