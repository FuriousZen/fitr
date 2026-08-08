"""Flask CLI commands."""

from __future__ import annotations

import click
from flask.cli import with_appcontext
from sqlalchemy import text

from .extensions import db


def register_cli(app) -> None:
    app.cli.add_command(init_db)
    app.cli.add_command(drop_db)
    app.cli.add_command(warm_clip)


@click.command("init-db")
@with_appcontext
def init_db():
    """Create the pgvector extension and all tables.

    CREATE EXTENSION requires superuser: pgvector is not a trusted extension
    (no `trusted = true` in vector.control), so this will fail if the app role
    is unprivileged. In that case run it once as postgres:

        sudo -u postgres psql -d fitr -c 'CREATE EXTENSION IF NOT EXISTS vector;'
    """
    try:
        db.session.execute(text("CREATE EXTENSION IF NOT EXISTS vector"))
        db.session.commit()
        click.echo("pgvector extension present")
    except Exception as exc:
        db.session.rollback()
        click.echo(f"could not create extension (needs superuser?): {exc}", err=True)
        click.echo("continuing; tables will fail if the extension is genuinely absent")

    db.create_all()
    version = db.session.execute(
        text("SELECT extversion FROM pg_extension WHERE extname='vector'")
    ).scalar()
    click.echo(f"schema created (pgvector {version})")


@click.command("drop-db")
@click.confirmation_option(prompt="Drop every fitr table?")
@with_appcontext
def drop_db():
    """Drop all tables defined by the models."""
    db.drop_all()
    click.echo("dropped")


@click.command("warm-clip")
@with_appcontext
def warm_clip():
    """Load CLIP weights and report how long it took."""
    from .services import services

    encoder = services().encoder
    encoder.load()
    click.echo(f"loaded {encoder.model_id} dim={encoder.dim} in {encoder.load_ms:.0f} ms")
