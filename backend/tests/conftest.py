"""Test fixtures.

Runs against a real PostgreSQL + pgvector database (``FITR_TEST_DATABASE_URL``,
default ``fitr_test``). The vector logic (cosine ordering, the HNSW index, the
L2 cache) is the whole point of this backend, so stubbing the database out
would test nothing worth testing.

CLIP is a different matter: loading the weights costs ~5 s and ~600 MB. By
default the suite uses ``FakeEncoder``, which is deterministic and exercises
every code path around the model. Tests that need the genuine article are
marked ``@pytest.mark.clip`` and run only with ``--run-clip``.

Nothing here talks to Gemini or OpenWeatherMap. There are no API keys in this
environment; those services are covered by fakes and by ``responses``.
"""

from __future__ import annotations

import hashlib
import io
import os

import numpy as np
import pytest
from PIL import Image, ImageDraw
from sqlalchemy import text

os.environ.setdefault("FITR_AUTH_MODE", "header")
# Never let an ambient key make the suite hit a real API.
os.environ.pop("GEMINI_API_KEY", None)
os.environ.pop("GOOGLE_API_KEY", None)
os.environ.pop("OPENWEATHERMAP_API_KEY", None)

from app import create_test_app  # noqa: E402
from app.extensions import db  # noqa: E402
from app.services.clip import ClipEncoder, _l2_normalize  # noqa: E402

TABLES = (
    "recommendation_feedback",
    "recommendations",
    "clothing_items",
    "image_embeddings",
)


def pytest_addoption(parser):
    parser.addoption(
        "--run-clip",
        action="store_true",
        default=False,
        help="run tests that load the real CLIP weights (slow, needs the model cached)",
    )


def pytest_configure(config):
    config.addinivalue_line("markers", "clip: requires the real CLIP model")


def pytest_collection_modifyitems(config, items):
    if config.getoption("--run-clip"):
        return
    skip = pytest.mark.skip(reason="needs --run-clip")
    for item in items:
        if "clip" in item.keywords:
            item.add_marker(skip)


class FakeEncoder(ClipEncoder):
    """Deterministic stand-in with CLIP's interface.

    Vectors are derived from a hash of the input, so identical bytes give
    identical vectors (which is what the content-addressed cache relies on) and
    different bytes give near-orthogonal ones. Output is L2-normalised, exactly
    as the real encoder's is.
    """

    def __init__(self, dim: int = 512, model_id: str = "fake/clip-test"):
        super().__init__(model_id=model_id, device="cpu", expected_dim=dim)
        self._dim = dim
        self.image_calls = 0
        self.text_calls = 0

    @property
    def loaded(self) -> bool:
        return True

    @property
    def dim(self) -> int:
        return self._dim

    def load(self) -> None:
        return None

    def _vector_for(self, payload: bytes) -> np.ndarray:
        seed = int.from_bytes(hashlib.sha256(payload).digest()[:8], "big") % (2**32)
        rng = np.random.default_rng(seed)
        return _l2_normalize(rng.standard_normal((1, self._dim)).astype(np.float32))[0]

    def encode_image_bytes(self, data: bytes):
        from app.services.clip import EncodeResult

        self.image_calls += 1
        return EncodeResult(vector=self._vector_for(data), elapsed_ms=1.0)

    def encode_texts(self, texts: list[str]) -> np.ndarray:
        self.text_calls += 1
        if not texts:
            return np.zeros((0, self._dim), dtype=np.float32)
        return np.stack([self._vector_for(t.encode("utf-8")) for t in texts])


def make_image(color=(30, 60, 140), size=(240, 320), label: str = "") -> bytes:
    """Deterministic JPEG. ``label`` changes the bytes without changing the look."""
    img = Image.new("RGB", size, (245, 245, 245))
    draw = ImageDraw.Draw(img)
    draw.rectangle([40, 60, size[0] - 40, size[1] - 60], fill=color)
    if label:
        draw.text((6, 6), label, fill=(0, 0, 0))
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=90)
    return buf.getvalue()


@pytest.fixture(scope="session")
def _real_encoder():
    encoder = ClipEncoder(
        model_id=os.environ.get("FITR_CLIP_MODEL", "openai/clip-vit-base-patch32"),
        expected_dim=512,
    )
    encoder.load()
    return encoder


@pytest.fixture(scope="session")
def _app_session():
    app = create_test_app()
    with app.app_context():
        db.session.execute(text("CREATE EXTENSION IF NOT EXISTS vector"))
        db.session.commit()
        db.create_all()
    return app


@pytest.fixture
def app(_app_session):
    """Function-scoped app context over a truncated database."""
    with _app_session.app_context():
        db.session.execute(
            text(f"TRUNCATE {', '.join(TABLES)} RESTART IDENTITY CASCADE")
        )
        db.session.commit()
        # Fresh fake encoder per test so call counters start at zero.
        registry = _app_session.extensions["fitr"]
        encoder = FakeEncoder(dim=_app_session.config["EMBED_DIM"])
        registry.encoder = encoder
        registry.cache.encoder = encoder
        registry.cache.clear_l1()
        registry.cache.stats.update({"l1": 0, "l2": 0, "miss": 0})
        registry.recommender.encoder = encoder
        registry.classifier.encoder = encoder
        registry.weather.clear_cache()
        registry.weather.api_key = ""
        registry.gemini.api_key = ""
        registry.gemini._client = None
        yield _app_session


@pytest.fixture
def client(app):
    return app.test_client()


@pytest.fixture
def services(app):
    return app.extensions["fitr"]


@pytest.fixture
def auth():
    return {"X-User-Id": "test-user"}


@pytest.fixture
def other_auth():
    return {"X-User-Id": "other-user"}


@pytest.fixture
def upload():
    """Build a multipart payload for an image upload."""

    def _upload(data: bytes, filename: str = "item.jpg", **fields):
        payload = {"image": (io.BytesIO(data), filename)}
        payload.update(fields)
        return payload

    return _upload


@pytest.fixture
def make_item(client, auth, upload):
    """Create a wardrobe item through the API and return its JSON."""

    def _make(name="item", type="T-Shirt", color="blue", label=None, **fields):
        image = make_image(label=label or name)
        resp = client.post(
            "/api/v1/wardrobe/items",
            data=upload(image, name=name, type=type, color=color, **fields),
            headers=auth,
            content_type="multipart/form-data",
        )
        assert resp.status_code == 201, resp.get_json()
        return resp.get_json()["item"]

    return _make
