"""Tests against the genuine CLIP weights.

Skipped unless ``--run-clip`` is passed, because they download/load ~605 MB.
These are the tests that prove the embeddings are real: that the vectors have
the right shape and norm, that ``get_image_features`` is being unpacked
correctly for the installed transformers major version, and that the
similarities are semantically meaningful rather than noise.
"""

from __future__ import annotations

import io

import numpy as np
import pytest
from PIL import Image, ImageDraw

pytestmark = pytest.mark.clip


def solid(color, size=(320, 320)) -> bytes:
    img = Image.new("RGB", size, (250, 250, 250))
    ImageDraw.Draw(img).rectangle([50, 50, size[0] - 50, size[1] - 50], fill=color)
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=92)
    return buf.getvalue()


def test_image_embedding_shape_and_norm(_real_encoder):
    result = _real_encoder.encode_image_bytes(solid((20, 40, 120)))
    assert result.vector.shape == (512,)
    assert result.vector.dtype == np.float32
    assert abs(float(np.linalg.norm(result.vector)) - 1.0) < 1e-4
    assert result.elapsed_ms > 0


def test_text_embedding_shape_and_norm(_real_encoder):
    vectors = _real_encoder.encode_texts(["a red shirt", "a blue coat"])
    assert vectors.shape == (2, 512)
    norms = np.linalg.norm(vectors, axis=1)
    assert np.allclose(norms, 1.0, atol=1e-4)


def test_embedding_is_deterministic(_real_encoder):
    image = solid((90, 30, 30))
    a = _real_encoder.encode_image_bytes(image).vector
    b = _real_encoder.encode_image_bytes(image).vector
    assert np.allclose(a, b, atol=1e-6), "content-addressed caching assumes determinism"


def test_pooler_output_is_the_projected_embedding(_real_encoder):
    """Guards the transformers 4.x -> 5.x return-type change.

    On transformers 5 ``get_image_features`` returns BaseModelOutputWithPooling
    whose ``pooler_output`` is post-projection (512-d), while
    ``last_hidden_state`` is pre-projection (768-d for ViT-B/32). Taking the
    wrong one silently produces garbage of the wrong dimensionality.
    """
    import torch
    from PIL import Image as PILImage

    _real_encoder.load()
    with PILImage.open(io.BytesIO(solid((10, 10, 10)))) as img:
        inputs = _real_encoder._processor(images=img.convert("RGB"), return_tensors="pt")
    with torch.inference_mode():
        raw = _real_encoder._model.get_image_features(**inputs)

    if hasattr(raw, "pooler_output"):
        assert raw.pooler_output.shape[-1] == 512
        assert raw.last_hidden_state.shape[-1] != 512
    else:  # transformers 4.x returned the tensor directly
        assert raw.shape[-1] == 512


def test_text_matches_the_colour_it_describes(_real_encoder):
    """A minimal but genuine semantic check: the embedding of a red swatch must
    sit closer to 'a red piece of clothing' than to 'a blue' one."""
    red = _real_encoder.encode_image_bytes(solid((200, 20, 20))).vector
    prompts = [
        "a photo of a red piece of clothing",
        "a photo of a blue piece of clothing",
        "a photo of a green piece of clothing",
    ]
    sims = _real_encoder.encode_texts(prompts) @ red
    assert int(np.argmax(sims)) == 0, f"expected red to win, got {sims}"


def test_different_colours_are_further_apart_than_identical_ones(_real_encoder):
    red_a = _real_encoder.encode_image_bytes(solid((200, 20, 20))).vector
    red_b = _real_encoder.encode_image_bytes(solid((205, 25, 25))).vector
    blue = _real_encoder.encode_image_bytes(solid((20, 20, 200))).vector

    assert float(red_a @ red_b) > float(red_a @ blue)


def test_zero_shot_classifier_returns_the_expected_shape(_real_encoder):
    from app.services.vision import ZeroShotClassifier
    from app.taxonomy import CLOTHING_TYPES, COLORS

    vec = _real_encoder.encode_image_bytes(solid((30, 30, 140))).vector
    result = ZeroShotClassifier(_real_encoder).classify(vec)

    assert result["type"] in CLOTHING_TYPES
    assert result["color"] in COLORS
    assert 0.0 <= result["type_confidence"] <= 1.0
    assert len(result["scores"]["type"]) == 3
    types_scores = [s["score"] for s in result["scores"]["type"]]
    assert types_scores == sorted(types_scores, reverse=True)


def test_projection_dim_matches_the_database_column(_real_encoder):
    assert _real_encoder.dim == 512, "vector(512) columns depend on this"


def test_dimension_mismatch_is_caught_at_load(_real_encoder):
    from app.services.clip import ClipEncoder, ClipUnavailableError

    encoder = ClipEncoder(model_id=_real_encoder.model_id, expected_dim=384)
    with pytest.raises(ClipUnavailableError, match="projection_dim"):
        encoder.load()
