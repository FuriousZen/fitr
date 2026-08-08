"""Fakes for the external APIs there are no credentials for."""

from __future__ import annotations

import json


class FakeResponse:
    def __init__(self, text: str):
        self.text = text


class FakeModels:
    def __init__(self, parent: "FakeGeminiClient"):
        self._parent = parent

    def generate_content(self, *, model, contents, config=None):
        self._parent.calls.append({"model": model, "contents": contents, "config": config})
        if self._parent.raises is not None:
            raise self._parent.raises
        payload = self._parent.responses.pop(0) if self._parent.responses else {"options": []}
        if isinstance(payload, str):
            return FakeResponse(payload)
        return FakeResponse(json.dumps(payload))


class FakeGeminiClient:
    """Stands in for ``google.genai.Client``.

    Matches only the surface this app uses —
    ``client.models.generate_content(model=..., contents=..., config=...)``
    returning an object with ``.text`` — which was verified against the real
    google-genai 2.17.0 signature by introspection.
    """

    def __init__(self, responses=None, raises: Exception | None = None):
        self.responses = list(responses or [])
        self.raises = raises
        self.calls: list[dict] = []
        self.models = FakeModels(self)
