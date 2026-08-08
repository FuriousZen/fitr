"""CLIP zero-shot recognition of wardrobe photos.

This is the "CLIP image recognition" half of the pipeline: given an image
embedding, score it against text embeddings of the label vocabulary and take
the softmax. No training, no labelled data — the same zero-shot transfer
protocol the CLIP paper uses, with the paper's "a photo of a ..." prompt
template.

Accuracy has not been measured on any clothing benchmark. Treat the returned
confidences as CLIP's cosine-similarity softmax, not as a validated classifier.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from ..taxonomy import (
    CLOTHING_TYPES,
    COLOR_PROMPT,
    COLORS,
    STYLE_PROMPT,
    STYLE_TAGS,
    TYPE_PROMPT,
    WEATHER_PROMPT,
    WEATHER_TAGS,
)
from .clip import ClipEncoder

#: CLIP's learned logit scale for the released ViT models is exp(4.6052) = 100.
LOGIT_SCALE = 100.0


def _softmax(x: np.ndarray) -> np.ndarray:
    shifted = x - np.max(x)
    exp = np.exp(shifted)
    return exp / exp.sum()


@dataclass(frozen=True)
class LabelScore:
    label: str
    score: float

    def as_dict(self) -> dict:
        return {"label": self.label, "score": round(float(self.score), 4)}


class ZeroShotClassifier:
    def __init__(self, encoder: ClipEncoder) -> None:
        self.encoder = encoder

    def _score(
        self, image_vec: np.ndarray, labels: tuple[str, ...], template: str
    ) -> list[LabelScore]:
        prompts = [template.format(label=label) for label in labels]
        text_vecs = self.encoder.encode_texts_cached(prompts)
        # Both sides are L2-normalised, so this dot product is cosine similarity.
        sims = text_vecs @ image_vec
        probs = _softmax(sims * LOGIT_SCALE)
        scored = [LabelScore(label, float(p)) for label, p in zip(labels, probs)]
        scored.sort(key=lambda s: s.score, reverse=True)
        return scored

    def classify(self, image_vec: np.ndarray, top_k: int = 3) -> dict:
        types_ = self._score(image_vec, CLOTHING_TYPES, TYPE_PROMPT)
        colors = self._score(image_vec, COLORS, COLOR_PROMPT)
        styles = self._score(image_vec, STYLE_TAGS, STYLE_PROMPT)
        weather = self._score(image_vec, WEATHER_TAGS, WEATHER_PROMPT)

        return {
            "type": types_[0].label,
            "type_confidence": round(types_[0].score, 4),
            "color": colors[0].label,
            "color_confidence": round(colors[0].score, 4),
            # Multi-label heads: CLIP's softmax over a mutually-exclusive label
            # set is not calibrated for multi-label output, so take the top-k
            # rather than thresholding a probability.
            "style_tags": [s.label for s in styles[:2]],
            "weather_tags": [w.label for w in weather[:2]],
            "scores": {
                "type": [s.as_dict() for s in types_[:top_k]],
                "color": [s.as_dict() for s in colors[:top_k]],
                "style": [s.as_dict() for s in styles[:top_k]],
                "weather": [s.as_dict() for s in weather[:top_k]],
            },
        }
