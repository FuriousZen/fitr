"""Blueprint registration."""

from __future__ import annotations

from . import health, metrics, recommendations, vision, wardrobe, weather


def register_blueprints(app) -> None:
    app.register_blueprint(health.bp)
    app.register_blueprint(wardrobe.bp)
    app.register_blueprint(vision.bp)
    app.register_blueprint(weather.bp)
    app.register_blueprint(recommendations.bp)
    app.register_blueprint(metrics.bp)
