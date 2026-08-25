"""Request authentication.

Two modes, selected by ``FITR_AUTH_MODE``:

``header`` (default)
    Trust ``X-User-Id``. Development and test only: anyone can claim any user
    id. This is what lets the benchmark and the test suite run with no
    credentials.

``firebase``
    Verify a Firebase ID token from ``Authorization: Bearer <jwt>`` using
    ``google.oauth2.id_token.verify_firebase_token``, which checks the
    signature against Google's public certs and the ``aud`` claim against
    ``FITR_FIREBASE_PROJECT_ID``. This is the mode a real deployment must use,
    and it lines up with the Firebase Authentication the iOS app already has.

The verification path has NOT been exercised against a real Firebase project in
this environment. There are no credentials here. It is written from the
documented API surface and covered only by a test that asserts a bad token is
rejected.
"""

from __future__ import annotations

import functools
import logging

from flask import current_app, g, request

from .errors import Unauthorized

log = logging.getLogger(__name__)


def _from_header() -> str:
    user_id = (request.headers.get("X-User-Id") or "").strip()
    if not user_id:
        raise Unauthorized("missing X-User-Id header")
    if len(user_id) > 128:
        raise Unauthorized("X-User-Id too long")
    return user_id


def _from_firebase() -> str:
    header = request.headers.get("Authorization") or ""
    if not header.lower().startswith("bearer "):
        raise Unauthorized("missing Authorization: Bearer <firebase-id-token>")
    token = header[7:].strip()
    project_id = current_app.config.get("FIREBASE_PROJECT_ID") or ""
    if not project_id:
        raise Unauthorized(
            "FITR_FIREBASE_PROJECT_ID must be set when FITR_AUTH_MODE=firebase"
        )
    try:
        from google.auth.transport import requests as google_requests
        from google.oauth2 import id_token as google_id_token

        claims = google_id_token.verify_firebase_token(
            token, google_requests.Request(), audience=project_id
        )
    except Exception as exc:
        log.info("firebase token rejected: %s", exc)
        raise Unauthorized("invalid Firebase ID token") from exc

    if not claims:
        raise Unauthorized("invalid Firebase ID token")
    subject = claims.get("sub") or claims.get("user_id")
    if not subject:
        raise Unauthorized("Firebase ID token has no subject claim")
    g.firebase_claims = claims
    return str(subject)


def reset_request_identity() -> None:
    """Drop any cached identity at the start of each request.

    ``g`` lives on the *application* context, not the request context. Flask
    only pushes a new application context if one is not already active, so a
    long-lived outer app context (which is exactly how the test suite and many
    scripts are written) would otherwise let one request's resolved user id
    leak into the next. Clearing explicitly per request removes that class of
    bug rather than relying on context nesting behaviour.
    """
    g.pop("user_id", None)
    g.pop("firebase_claims", None)


def current_user_id() -> str:
    cached = g.get("user_id")
    if cached:
        return cached
    mode = (current_app.config.get("AUTH_MODE") or "header").lower()
    if mode == "firebase":
        user_id = _from_firebase()
    elif mode == "header":
        user_id = _from_header()
    else:
        raise Unauthorized(f"unknown FITR_AUTH_MODE {mode!r}")
    g.user_id = user_id
    return user_id


def require_user(view):
    @functools.wraps(view)
    def wrapper(*args, **kwargs):
        current_user_id()
        return view(*args, **kwargs)

    return wrapper
