"""CLIP image/text encoder.

Library choice — HuggingFace ``transformers`` over ``open_clip_torch``:

* ``transformers`` + ``torchvision`` were already required for the image
  pipeline, so open_clip's extra dependency chain (notably ``timm``) buys
  nothing here; both ship the same ViT-B/32 weights at the same 512 dims.
* The one real argument for open_clip is API churn: ``transformers`` 5.0
  changed ``get_image_features()`` from returning a bare tensor to returning
  ``BaseModelOutputWithPooling``. That is handled explicitly by ``_pooled()``
  below, which supports both shapes, and ``requirements.txt`` pins the major
  version. This was verified empirically against the installed 5.14.1, not
  taken from documentation.

Both encoders L2-normalise before returning, so cosine similarity over stored
vectors is a dot product and ``vector_cosine_ops`` behaves as expected.
``get_image_features(...).pooler_output`` is *not* normalised by the model —
CLIPModel.forward normalises internally before computing logits, so callers
using the feature helpers must do it themselves.
"""

from __future__ import annotations

import io
import logging
import threading
import time
from dataclasses import dataclass

import numpy as np

log = logging.getLogger(__name__)


@dataclass(frozen=True)
class EncodeResult:
    vector: np.ndarray
    elapsed_ms: float


class ClipUnavailableError(RuntimeError):
    """Raised when the CLIP weights cannot be loaded."""


def _pooled(output):
    """Extract the projected embedding tensor from a ``get_*_features`` result.

    transformers >= 5 returns ``BaseModelOutputWithPooling`` whose
    ``pooler_output`` has already had the projection applied; transformers 4.x
    returned that tensor directly.
    """
    pooler = getattr(output, "pooler_output", None)
    if pooler is not None:
        return pooler
    return output


def _l2_normalize(mat: np.ndarray) -> np.ndarray:
    norms = np.linalg.norm(mat, axis=-1, keepdims=True)
    norms = np.where(norms == 0.0, 1.0, norms)
    return (mat / norms).astype(np.float32)


class ClipEncoder:
    """Lazily-loaded CLIP encoder. Thread-safe.

    The Flask dev server and gunicorn's sync worker are both multi-threaded in
    practice, and torch modules are not re-entrant across a ``from_pretrained``
    call, so loading is guarded by a lock. Inference itself is left unguarded:
    a forward pass on a module in eval mode with no in-place state is safe to
    run concurrently, and serialising it would destroy throughput.
    """

    def __init__(
        self,
        model_id: str = "openai/clip-vit-base-patch32",
        device: str = "cpu",
        expected_dim: int | None = None,
        torch_threads: int = 0,
        local_files_only: bool = False,
    ) -> None:
        self.model_id = model_id
        self.device = device
        self.expected_dim = expected_dim
        self.torch_threads = torch_threads
        #: When True, never contact the HuggingFace Hub. `from_pretrained`
        #: otherwise makes several HTTP calls per load even on a warm cache, so
        #: a deployment with pre-baked weights should turn this on.
        self.local_files_only = local_files_only
        self._model = None
        self._processor = None
        self._lock = threading.Lock()
        self._load_ms: float | None = None
        self._text_cache: dict[str, np.ndarray] = {}
        self._text_cache_lock = threading.Lock()

    # -- lifecycle ---------------------------------------------------------

    @property
    def loaded(self) -> bool:
        return self._model is not None

    @property
    def load_ms(self) -> float | None:
        return self._load_ms

    def load(self) -> None:
        """Load weights. Idempotent; safe to call from multiple threads."""
        if self._model is not None:
            return
        with self._lock:
            if self._model is not None:
                return
            started = time.perf_counter()
            try:
                import torch
                from transformers import CLIPModel, CLIPProcessor
            except Exception as exc:  # pragma: no cover - import environment
                raise ClipUnavailableError(f"torch/transformers unavailable: {exc}") from exc

            if self.torch_threads and self.torch_threads > 0:
                torch.set_num_threads(self.torch_threads)

            try:
                kwargs = {"local_files_only": True} if self.local_files_only else {}
                model = CLIPModel.from_pretrained(self.model_id, **kwargs)
                processor = CLIPProcessor.from_pretrained(self.model_id, **kwargs)
            except Exception as exc:
                raise ClipUnavailableError(
                    f"could not load CLIP model {self.model_id!r}: {exc}"
                ) from exc

            model.eval()
            model.to(self.device)

            dim = int(getattr(model.config, "projection_dim", 0) or 0)
            if self.expected_dim and dim and dim != self.expected_dim:
                raise ClipUnavailableError(
                    f"model {self.model_id!r} has projection_dim={dim} but the "
                    f"database vector columns are {self.expected_dim}-dimensional. "
                    f"Set FITR_EMBED_DIM={dim} and recreate the schema, or pick a "
                    f"different model."
                )

            self._torch = torch
            self._model = model
            self._processor = processor
            self._load_ms = (time.perf_counter() - started) * 1000.0
            log.info(
                "loaded CLIP %s (dim=%s) in %.0f ms", self.model_id, dim, self._load_ms
            )

    @property
    def dim(self) -> int:
        if self._model is None:
            return int(self.expected_dim or 0)
        return int(self._model.config.projection_dim)

    # -- encoding ----------------------------------------------------------

    def encode_image_bytes(self, data: bytes) -> EncodeResult:
        from PIL import Image

        self.load()
        started = time.perf_counter()
        with Image.open(io.BytesIO(data)) as img:
            image = img.convert("RGB")
            inputs = self._processor(images=image, return_tensors="pt")
        inputs = {k: v.to(self.device) for k, v in inputs.items()}
        with self._torch.inference_mode():
            features = _pooled(self._model.get_image_features(**inputs))
        vec = features.detach().cpu().numpy().astype(np.float32)
        vec = _l2_normalize(vec)[0]
        return EncodeResult(vector=vec, elapsed_ms=(time.perf_counter() - started) * 1000.0)

    def encode_texts(self, texts: list[str]) -> np.ndarray:
        """Encode a batch of strings. Returns an ``(n, dim)`` normalised array."""
        if not texts:
            return np.zeros((0, self.dim), dtype=np.float32)
        self.load()
        inputs = self._processor(
            text=texts, return_tensors="pt", padding=True, truncation=True
        )
        inputs = {k: v.to(self.device) for k, v in inputs.items()}
        with self._torch.inference_mode():
            features = _pooled(self._model.get_text_features(**inputs))
        mat = features.detach().cpu().numpy().astype(np.float32)
        return _l2_normalize(mat)

    def encode_text(self, text: str) -> np.ndarray:
        return self.encode_texts([text])[0]

    def encode_texts_cached(self, texts: list[str]) -> np.ndarray:
        """``encode_texts`` with an unbounded in-process memo.

        Used for the fixed label vocabularies (clothing types, colours, style
        tags), which are small, constant, and re-encoded on every zero-shot
        classification. Not used for user-supplied query text.
        """
        missing = [t for t in texts if t not in self._text_cache]
        if missing:
            encoded = self.encode_texts(missing)
            with self._text_cache_lock:
                for text, vec in zip(missing, encoded):
                    self._text_cache[text] = vec
        return np.stack([self._text_cache[t] for t in texts])

    def health(self) -> dict:
        return {
            "model_id": self.model_id,
            "device": self.device,
            "loaded": self.loaded,
            "dim": self.dim,
            "load_ms": round(self._load_ms, 2) if self._load_ms is not None else None,
            "text_labels_cached": len(self._text_cache),
            "local_files_only": self.local_files_only,
        }
