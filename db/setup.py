"""Create the faker schema, its stored procedures and lookup data.

    DATABASE_URL=postgresql://user:pass@host/db  python db/setup.py

Steps: run db/sql/*.sql in order (drops and recreates schema `faker`), run the
locale seed files db/seed/*.sql, COPY the large lookup tables from
db/data/*.csv.gz, then CALL faker.refresh_weights() and ANALYZE.
"""
from __future__ import annotations

import gzip
import os
import sys
import time
from pathlib import Path

import psycopg

DB = Path(__file__).resolve().parent

# table -> columns of its CSV file, in load order (states before transitions)
CSV_TABLES = {
    "names": ["locale", "kind", "gender", "value", "weight"],
    "places": ["locale", "postal_code", "city", "region", "region_code", "weight"],
    "words": ["locale", "kind", "gender", "value", "alt", "weight"],
    "markov_states": ["state_id", "locale", "w1", "w2", "start_weight"],
    "markov_transitions": ["state_id", "next_word", "next_state_id", "weight"],
}


def step(label: str):
    print(f"{label} ...", end=" ", flush=True)
    return time.perf_counter()


def done(t0: float, extra: str = ""):
    print(f"{time.perf_counter() - t0:.1f}s {extra}".rstrip())


def copy_csv(cur: psycopg.Cursor, table: str, columns: list[str]) -> None:
    sql = f"COPY faker.{table} ({', '.join(columns)}) FROM STDIN WITH (FORMAT csv, HEADER true)"
    with gzip.open(DB / "data" / f"{table}.csv.gz", "rb") as fh, cur.copy(sql) as copy:
        while chunk := fh.read(1 << 20):
            copy.write(chunk)


def main() -> int:
    url = os.environ.get("DATABASE_URL")
    if not url:
        print("Set DATABASE_URL, e.g. postgresql://faker:faker@localhost:5544/faker", file=sys.stderr)
        return 1
    with psycopg.connect(url, autocommit=False) as conn, conn.cursor() as cur:
        for path in sorted((DB / "sql").glob("*.sql")):
            t0 = step(f"sql   {path.name}")
            cur.execute(path.read_text(encoding="utf-8"))
            done(t0)
        for path in sorted((DB / "seed").glob("*.sql")):
            t0 = step(f"seed  {path.name}")
            cur.execute(path.read_text(encoding="utf-8"))
            done(t0)
        for table, columns in CSV_TABLES.items():
            t0 = step(f"copy  {table}")
            copy_csv(cur, table, columns)
            done(t0, f"({cur.rowcount} rows)")
        t0 = step("call  faker.refresh_weights()")
        cur.execute("CALL faker.refresh_weights()")
        done(t0)
        conn.commit()
    with psycopg.connect(url, autocommit=True) as conn:
        t0 = step("analyze")
        conn.execute("ANALYZE faker.names, faker.places, faker.words, faker.formats, "
                     "faker.markov_states, faker.markov_transitions, faker.body_stats, faker.locales")
        done(t0)
        rows = conn.execute("SELECT locale, \"table\", list, entries FROM faker.lookup_sizes "
                            "WHERE \"table\" IN ('names', 'places', 'markov_transitions') "
                            "ORDER BY 1, 2, 3").fetchall()
        for row in rows:
            print(f"  {row[0]}  {row[1]:<20} {row[2]:<30} {row[3]:>8}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
