"""Uniform JSON error envelope.

Every failure — expected or not — comes back as
``{"error": {"code": "...", "message": "..."}}`` with an appropriate status, so
the Swift client only ever has to decode one error shape.
"""

from __future__ import annotations

import logging

from werkzeug.exceptions import HTTPException

log = logging.getLogger(__name__)


class ApiError(Exception):
    status_code = 400
    code = "bad_request"

    def __init__(self, message: str, status_code: int | None = None, code: str | None = None):
        super().__init__(message)
        self.message = message
        if status_code is not None:
            self.status_code = status_code
        if code is not None:
            self.code = code

    def to_dict(self) -> dict:
        return {"error": {"code": self.code, "message": self.message}}


class NotFound(ApiError):
    status_code = 404
    code = "not_found"


class Unauthorized(ApiError):
    status_code = 401
    code = "unauthorized"


class ValidationError(ApiError):
    status_code = 422
    code = "validation_error"


class ServiceUnavailable(ApiError):
    status_code = 503
    code = "service_unavailable"


class PayloadTooLarge(ApiError):
    status_code = 413
    code = "payload_too_large"


def register_error_handlers(app) -> None:
    @app.errorhandler(ApiError)
    def _handle_api_error(exc: ApiError):
        return exc.to_dict(), exc.status_code

    @app.errorhandler(HTTPException)
    def _handle_http_error(exc: HTTPException):
        return {
            "error": {
                "code": (exc.name or "http_error").lower().replace(" ", "_"),
                "message": exc.description or "",
            }
        }, exc.code or 500

    @app.errorhandler(Exception)
    def _handle_unexpected(exc: Exception):
        log.exception("unhandled error")
        return {
            "error": {"code": "internal_error", "message": "internal server error"}
        }, 500
