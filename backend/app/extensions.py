"""Flask extension singletons.

Kept in their own module so models can import ``db`` without importing the app
factory (the pattern the Flask docs recommend for app factories).
"""

from __future__ import annotations

from flask_sqlalchemy import SQLAlchemy
from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    """SQLAlchemy 2.0 declarative base, handed to Flask-SQLAlchemy."""


db = SQLAlchemy(model_class=Base)
