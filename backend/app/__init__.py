"""Application factory."""

from __future__ import annotations

import logging
import os

from dotenv import load_dotenv
from flask import Flask
from flask_cors import CORS

# Load backend/.env before Config's class body reads os.environ.
load_dotenv(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".env"))

from .config import Config, TestConfig  # noqa: E402
from .errors import register_error_handlers  # noqa: E402
from .extensions import db  # noqa: E402

__all__ = ["create_app", "db"]


def create_app(config_object=None, **overrides) -> Flask:
    app = Flask(__name__)
    app.config.from_object(config_object or Config)
    if overrides:
        app.config.from_mapping(overrides)

    logging.basicConfig(
        level=os.environ.get("FITR_LOG_LEVEL", "INFO").upper(),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )

    db.init_app(app)
    cors_origins = list(app.config.get("CORS_ORIGINS") or [])
    if cors_origins:
        CORS(app, origins=cors_origins)

    # Import inside the factory so `app.models` is registered on the metadata
    # exactly once per process and there is no import cycle with extensions.
    from . import models  # noqa: F401
    from .api import register_blueprints
    from .cli import register_cli
    from .services import build_services

    from .auth import reset_request_identity

    app.before_request(reset_request_identity)

    app.extensions["fitr"] = build_services(app.config)
    register_blueprints(app)
    register_error_handlers(app)
    register_cli(app)

    if app.config.get("CLIP_EAGER"):
        # Pay the ~600 MB weight load at boot rather than on a user's request.
        app.extensions["fitr"].encoder.load()

    return app


def create_test_app(**overrides) -> Flask:
    return create_app(TestConfig, **overrides)
