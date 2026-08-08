"""Shared request-parsing helpers."""

from __future__ import annotations

import base64
import binascii

from flask import current_app, request

from ..errors import PayloadTooLarge, ValidationError

#: Magic-byte prefixes for the formats Pillow will be asked to decode.
_IMAGE_SIGNATURES = (
    b"\xff\xd8\xff",          # JPEG
    b"\x89PNG\r\n\x1a\n",     # PNG
    b"GIF87a",
    b"GIF89a",
    b"RIFF",                  # WEBP (RIFF....WEBP)
    b"BM",                    # BMP
    b"II*\x00",               # TIFF little-endian
    b"MM\x00*",               # TIFF big-endian
)


def json_body() -> dict:
    body = request.get_json(silent=True)
    if body is None:
        return {}
    if not isinstance(body, dict):
        raise ValidationError("request body must be a JSON object")
    return body


def read_image_bytes(field: str = "image", required: bool = True) -> bytes | None:
    """Pull image bytes from a multipart upload or a base64 JSON field.

    Accepts either ``multipart/form-data`` with a file part named ``image``, or
    ``application/json`` with ``{"image_base64": "..."}`` (optionally a
    ``data:image/jpeg;base64,`` data URL, as produced by a browser or by
    ``UIImage`` bridging code).
    """
    max_bytes = current_app.config["MAX_IMAGE_BYTES"]
    data: bytes | None = None

    if field in request.files:
        data = request.files[field].read()
    else:
        body = json_body()
        encoded = body.get("image_base64")
        if encoded:
            if not isinstance(encoded, str):
                raise ValidationError("image_base64 must be a string")
            if encoded.startswith("data:"):
                _, _, encoded = encoded.partition(",")
            try:
                data = base64.b64decode(encoded, validate=True)
            except (binascii.Error, ValueError) as exc:
                raise ValidationError(f"image_base64 is not valid base64: {exc}") from exc

    if data is None or len(data) == 0:
        if required:
            raise ValidationError(
                "no image provided: send multipart field 'image' or JSON 'image_base64'"
            )
        return None

    if len(data) > max_bytes:
        raise PayloadTooLarge(
            f"image is {len(data)} bytes, limit is {max_bytes} "
            f"(raise FITR_MAX_IMAGE_BYTES to change)"
        )
    if not data.startswith(_IMAGE_SIGNATURES):
        raise ValidationError("uploaded bytes are not a recognised image format")
    return data


def form_or_json() -> dict:
    """Merge form fields and JSON body into one mapping.

    Multipart requests carry metadata as form fields; JSON requests carry it in
    the body. Endpoints that accept both shouldn't care which was used.
    """
    merged: dict = {}
    if request.form:
        merged.update(request.form.to_dict(flat=True))
    body = request.get_json(silent=True)
    if isinstance(body, dict):
        merged.update(body)
    return merged


def get_str(data: dict, key: str, default: str = "", required: bool = False) -> str:
    value = data.get(key, default)
    if value is None:
        value = default
    value = str(value).strip()
    if required and not value:
        raise ValidationError(f"{key} is required")
    return value


def get_int(data: dict, key: str, default: int, minimum: int = 1, maximum: int = 200) -> int:
    raw = data.get(key, default)
    try:
        value = int(raw)
    except (TypeError, ValueError):
        raise ValidationError(f"{key} must be an integer") from None
    return max(minimum, min(maximum, value))


def get_bool(data: dict, key: str, default: bool = False) -> bool:
    raw = data.get(key, default)
    if isinstance(raw, bool):
        return raw
    return str(raw).strip().lower() in {"1", "true", "yes", "on"}


def get_float(data: dict, key: str) -> float | None:
    raw = data.get(key)
    if raw is None or raw == "":
        return None
    try:
        return float(raw)
    except (TypeError, ValueError):
        raise ValidationError(f"{key} must be a number") from None


def get_str_list(data: dict, key: str) -> list[str]:
    """Read a list that may arrive as a JSON array or a comma-separated string."""
    raw = data.get(key)
    if raw is None:
        return []
    if isinstance(raw, list):
        return [str(v).strip() for v in raw if str(v).strip()]
    return [part.strip() for part in str(raw).split(",") if part.strip()]
