"""Database access: every piece of data comes from the faker.* stored procedures."""
from __future__ import annotations

import os
import threading
from typing import Any

from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

DEFAULT_URL = "postgresql://faker:faker@127.0.0.1:5544/faker"

_pool: ConnectionPool | None = None
_lock = threading.Lock()


def pool() -> ConnectionPool:
    """A small lazily opened pool. prepare_threshold=None keeps it compatible
    with transaction-mode poolers (PgBouncer, Neon's -pooler endpoint)."""
    global _pool
    with _lock:
        if _pool is None:
            _pool = ConnectionPool(
                os.environ.get("DATABASE_URL", DEFAULT_URL),
                min_size=1,
                max_size=int(os.environ.get("DB_POOL_SIZE", "4")),
                kwargs={"autocommit": True, "prepare_threshold": None, "row_factory": dict_row},
                check=ConnectionPool.check_connection,
                open=True,
            )
        return _pool


def query(sql: str, params: tuple | dict = ()) -> list[dict[str, Any]]:
    with pool().connection() as conn:
        return conn.execute(sql, params).fetchall()


def list_locales() -> list[dict[str, Any]]:
    return query("SELECT code, title FROM faker.list_locales()")


def generate_users(locale: str, seed: int, batch: int, size: int, with_text: bool) -> list[dict[str, Any]]:
    return query(
        """SELECT u.*, faker.format_coordinates(u.latitude, u.longitude, 'dms') AS coordinates
           FROM faker.generate_users(%s, %s, %s, %s, %s) u""",
        (locale, seed, batch, size, with_text),
    )


def sample(locale: str, seed: int, size: int) -> list[dict[str, Any]]:
    """Columns needed by the distribution page, for `size` users from position 0."""
    return query(
        """SELECT latitude, longitude, gender, height_cm, weight_kg, eye_color, blood_type
           FROM faker.generate_users(%s, %s, 0, %s, false)""",
        (locale, seed, size),
    )


def benchmark(locale: str, users: int, with_text: bool) -> dict[str, Any]:
    return query("SELECT * FROM faker.benchmark(%s, %s, %s)", (locale, users, with_text))[0]


def body_stats(locale: str) -> dict[str, dict[str, float]]:
    rows = query("SELECT gender, height_mean_cm, height_sd_cm FROM faker.body_stats WHERE locale = %s", (locale,))
    return {r["gender"]: r for r in rows}


def word_weights(locale: str, kind: str) -> list[dict[str, Any]]:
    return query(
        "SELECT value, weight FROM faker.words WHERE locale = %s AND kind = %s ORDER BY weight DESC, value",
        (locale, kind),
    )


def lookup_sizes() -> list[dict[str, Any]]:
    return query('SELECT locale, "table", list, entries FROM faker.lookup_sizes ORDER BY locale, "table", list')
