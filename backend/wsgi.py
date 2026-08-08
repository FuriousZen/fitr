"""WSGI entrypoint.

    gunicorn -w 2 -t 120 -b 0.0.0.0:8000 wsgi:app

Note on workers: each worker process loads its own copy of the CLIP weights
(~600 MB resident), and each has its own L1 cache. The Postgres L2 cache is
what keeps a multi-worker deployment from recomputing the same embedding once
per worker.
"""

from app import create_app

app = create_app()
