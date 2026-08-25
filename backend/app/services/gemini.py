"""Gemini client for outfit generation.

Uses the current unified SDK, ``google-genai`` (``from google import genai``).
The old ``google-generativeai`` package is deprecated and reached end of life on
2025-11-30; it must not be used.

Verified against the installed google-genai 2.17.0 by introspection:

* ``genai.Client(api_key=...)``
* ``client.models.generate_content(model=..., contents=..., config=...)``
* ``types.GenerateContentConfig(response_mime_type=..., response_schema=...)``
  where ``response_schema`` accepts a lowercase JSON-Schema-style dict and
  coerces it to ``types.Schema``.
* ``types.HttpOptions(timeout=...)`` is in **milliseconds**, not seconds.

Note on model ids: the Swift app names ``gemini-3.7-flash`` and
``gemini-3.1-pro`` directly, independently of this module. The default here is
``gemini-3.6-flash``; override with ``FITR_GEMINI_MODEL``.

There is no API key in this environment, so no live call has ever been made
from this repo. Every test exercises this module against a fake client.
"""

from __future__ import annotations

import json
import logging
import time
from dataclasses import dataclass

log = logging.getLogger(__name__)

#: Response schema for outfit generation. ``options`` is ranked best-first.
OUTFIT_SCHEMA: dict = {
    "type": "object",
    "properties": {
        "options": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "item_ids": {"type": "array", "items": {"type": "string"}},
                    "description": {"type": "string"},
                },
                "required": ["item_ids", "description"],
            },
        }
    },
    "required": ["options"],
}


class GeminiUnavailableError(RuntimeError):
    pass


@dataclass(frozen=True)
class GeminiResult:
    options: list[dict]
    model: str
    elapsed_ms: float
    raw_text: str


class GeminiService:
    def __init__(
        self,
        api_key: str = "",
        model: str = "gemini-3.6-flash",
        temperature: float = 0.7,
        timeout_s: float = 30.0,
        client=None,
    ) -> None:
        self.api_key = api_key or ""
        self.model = model
        self.temperature = temperature
        self.timeout_s = timeout_s
        self._client = client
        self._client_error: str | None = None

    @property
    def configured(self) -> bool:
        return bool(self.api_key) or self._client is not None

    def _get_client(self):
        if self._client is not None:
            return self._client
        if not self.api_key:
            raise GeminiUnavailableError(
                "GEMINI_API_KEY / GOOGLE_API_KEY is not set; outfit generation "
                "falls back to the CLIP-only ranker"
            )
        try:
            from google import genai
            from google.genai import types
        except Exception as exc:  # pragma: no cover - import environment
            raise GeminiUnavailableError(f"google-genai unavailable: {exc}") from exc
        self._client = genai.Client(
            api_key=self.api_key,
            http_options=types.HttpOptions(timeout=int(self.timeout_s * 1000)),
        )
        return self._client

    # -- prompt ------------------------------------------------------------

    @staticmethod
    def build_prompt(vibe: str, weather: dict, candidates: list[dict]) -> str:
        """Render the outfit prompt.

        ``candidates`` have already been narrowed by CLIP similarity, so the
        prompt stays small regardless of wardrobe size.
        """
        slim = [
            {
                "id": c["id"],
                "type": c.get("type"),
                "color": c.get("color"),
                "name": c.get("name"),
                "weather_tags": c.get("weather_tags", []),
                "style_tags": c.get("style_tags", []),
            }
            for c in candidates
        ]
        units = weather.get("units", "imperial")
        degrees = "F" if units == "imperial" else ("C" if units == "metric" else "K")
        return (
            "You are a stylist. Build up to 3 distinct outfits from the wardrobe "
            "items below, ranked best first.\n\n"
            f"Vibe: {vibe or 'everyday'}\n"
            f"Weather: {json.dumps(weather)}  (temperature is in degrees {degrees})\n\n"
            f"Wardrobe items (pre-filtered for relevance):\n{json.dumps(slim)}\n\n"
            "Rules:\n"
            "- Only use ids from the list above. Never invent an id.\n"
            "- Each outfit needs at least one top and one bottom, or a dress.\n"
            "- Do not put two items of the same type in one outfit, except "
            "accessories.\n"
            "- Cold (<50F / 10C): add a layer. Hot (>77F / 25C): keep it light. "
            "Rainy or snowy: prefer water-resistant items.\n"
            "- Outfits must differ from each other by at least one item.\n"
            "- If the wardrobe cannot produce a sensible outfit, return an empty "
            "options array rather than a bad outfit.\n"
            "- Write each description as one short sentence for the wearer."
        )

    # -- call --------------------------------------------------------------

    def generate_outfits(
        self, vibe: str, weather: dict, candidates: list[dict], num_options: int = 3
    ) -> GeminiResult:
        client = self._get_client()
        prompt = self.build_prompt(vibe, weather, candidates)

        try:
            from google.genai import types

            config = types.GenerateContentConfig(
                temperature=self.temperature,
                response_mime_type="application/json",
                response_schema=OUTFIT_SCHEMA,
            )
        except Exception:  # pragma: no cover - only when the SDK is absent
            config = {
                "temperature": self.temperature,
                "response_mime_type": "application/json",
                "response_schema": OUTFIT_SCHEMA,
            }

        started = time.perf_counter()
        try:
            response = client.models.generate_content(
                model=self.model, contents=prompt, config=config
            )
        except Exception as exc:
            raise GeminiUnavailableError(f"Gemini request failed: {exc}") from exc
        elapsed_ms = (time.perf_counter() - started) * 1000.0

        text = getattr(response, "text", None)
        if not text:
            raise GeminiUnavailableError("Gemini returned an empty response")

        try:
            payload = json.loads(text)
        except json.JSONDecodeError as exc:
            raise GeminiUnavailableError(
                f"Gemini returned non-JSON despite response_mime_type: {exc}"
            ) from exc

        valid_ids = {c["id"] for c in candidates}
        options: list[dict] = []
        for raw in (payload.get("options") or [])[:num_options]:
            # The model is instructed never to invent ids, but a hallucinated id
            # would otherwise 500 the request downstream, so filter defensively.
            item_ids = [i for i in (raw.get("item_ids") or []) if i in valid_ids]
            if not item_ids:
                continue
            options.append(
                {
                    "rank": len(options) + 1,
                    "item_ids": item_ids,
                    "description": (raw.get("description") or "").strip(),
                }
            )

        return GeminiResult(
            options=options, model=self.model, elapsed_ms=elapsed_ms, raw_text=text
        )

    def health(self) -> dict:
        return {
            "configured": self.configured,
            "model": self.model,
            "temperature": self.temperature,
        }
