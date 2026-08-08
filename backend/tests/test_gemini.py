"""Gemini service tests.

No API key exists in this environment, so no live Gemini call has ever been
made from this repository. These tests drive ``GeminiService`` against
``FakeGeminiClient``, which mirrors the call signature verified against the
installed google-genai 2.17.0.
"""

from __future__ import annotations

import json

import pytest

from app.services.gemini import OUTFIT_SCHEMA, GeminiService, GeminiUnavailableError

from .fakes import FakeGeminiClient

CANDIDATES = [
    {"id": "a", "type": "T-Shirt", "color": "white", "name": "white tee",
     "weather_tags": ["Warm"], "style_tags": ["casual"]},
    {"id": "b", "type": "Jeans", "color": "blue", "name": "blue jeans",
     "weather_tags": ["Cool"], "style_tags": ["casual"]},
    {"id": "c", "type": "Jacket", "color": "black", "name": "black jacket",
     "weather_tags": ["Cold"], "style_tags": ["casual"]},
]
WEATHER = {
    "temperature": 48.2,
    "condition": "Rainy",
    "humidity": 82,
    "wind_speed": 7.6,
    "location": "Charlottesville",
    "units": "imperial",
}


def test_unconfigured_service_reports_itself():
    svc = GeminiService(api_key="")
    assert svc.configured is False
    with pytest.raises(GeminiUnavailableError, match="GEMINI_API_KEY"):
        svc.generate_outfits("casual", WEATHER, CANDIDATES)


def test_generates_ranked_options():
    client = FakeGeminiClient(
        responses=[
            {
                "options": [
                    {"item_ids": ["a", "b"], "description": "Tee and jeans."},
                    {"item_ids": ["a", "b", "c"], "description": "Add the jacket."},
                ]
            }
        ]
    )
    svc = GeminiService(api_key="", model="gemini-3.6-flash", client=client)

    result = svc.generate_outfits("casual", WEATHER, CANDIDATES, num_options=3)

    assert [o["rank"] for o in result.options] == [1, 2]
    assert result.options[0]["item_ids"] == ["a", "b"]
    assert result.model == "gemini-3.6-flash"
    assert result.elapsed_ms >= 0


def test_request_uses_json_mime_type_and_schema():
    client = FakeGeminiClient(responses=[{"options": []}])
    svc = GeminiService(api_key="", client=client)
    svc.generate_outfits("casual", WEATHER, CANDIDATES)

    config = client.calls[0]["config"]
    assert config.response_mime_type == "application/json"
    assert config.response_schema == OUTFIT_SCHEMA


def test_hallucinated_item_ids_are_filtered_out():
    """The model is told never to invent ids; if it does anyway, the id must
    not reach the database lookup."""
    client = FakeGeminiClient(
        responses=[
            {
                "options": [
                    {"item_ids": ["a", "does-not-exist"], "description": "one"},
                    {"item_ids": ["nope", "also-nope"], "description": "two"},
                ]
            }
        ]
    )
    svc = GeminiService(api_key="", client=client)
    result = svc.generate_outfits("casual", WEATHER, CANDIDATES)

    assert result.options[0]["item_ids"] == ["a"]
    assert len(result.options) == 1, "an option with no valid ids must be dropped"


def test_num_options_is_capped():
    client = FakeGeminiClient(
        responses=[
            {"options": [{"item_ids": ["a"], "description": str(i)} for i in range(9)]}
        ]
    )
    svc = GeminiService(api_key="", client=client)
    assert len(svc.generate_outfits("casual", WEATHER, CANDIDATES, num_options=2).options) == 2


def test_non_json_response_is_an_error_not_a_crash():
    client = FakeGeminiClient(responses=["I'd suggest the blue jeans!"])
    svc = GeminiService(api_key="", client=client)
    with pytest.raises(GeminiUnavailableError, match="non-JSON"):
        svc.generate_outfits("casual", WEATHER, CANDIDATES)


def test_empty_response_is_an_error():
    client = FakeGeminiClient(responses=[""])
    svc = GeminiService(api_key="", client=client)
    with pytest.raises(GeminiUnavailableError, match="empty"):
        svc.generate_outfits("casual", WEATHER, CANDIDATES)


def test_transport_failure_is_wrapped():
    client = FakeGeminiClient(raises=RuntimeError("connection reset"))
    svc = GeminiService(api_key="", client=client)
    with pytest.raises(GeminiUnavailableError, match="connection reset"):
        svc.generate_outfits("casual", WEATHER, CANDIDATES)


def test_prompt_contains_the_candidates_and_the_weather():
    prompt = GeminiService.build_prompt("formal", WEATHER, CANDIDATES)
    assert "formal" in prompt
    assert "Rainy" in prompt
    for candidate in CANDIDATES:
        assert candidate["id"] in prompt
    assert "degrees F" in prompt, "unit must be stated so the model reads temps correctly"
    assert "Never invent an id" in prompt


def test_prompt_states_celsius_for_metric():
    prompt = GeminiService.build_prompt("casual", {**WEATHER, "units": "metric"}, CANDIDATES)
    assert "degrees C" in prompt


def test_prompt_only_carries_the_shortlist_not_the_whole_wardrobe():
    """CLIP narrows the candidate set; prompt size must track the shortlist,
    which is what keeps generation latency flat as a wardrobe grows."""
    prompt = GeminiService.build_prompt("casual", WEATHER, CANDIDATES[:1])
    listed = json.loads(prompt.split("relevance):\n")[1].split("\n\n")[0])
    assert [c["id"] for c in listed] == ["a"]

    bigger = GeminiService.build_prompt("casual", WEATHER, CANDIDATES)
    assert len(bigger) > len(prompt)


def test_schema_is_a_valid_google_schema():
    """response_schema is handed to the SDK as a lowercase JSON-Schema dict;
    confirm the SDK really does coerce it."""
    types = pytest.importorskip("google.genai.types")
    schema = types.Schema(**OUTFIT_SCHEMA)
    assert schema.type == types.Type.OBJECT
    assert schema.properties["options"].type == types.Type.ARRAY
