"""Benchmark the SQL faker and print a Markdown table (--out FILE also saves it).

    DATABASE_URL=postgresql://...  python scripts/benchmark.py [--users 100000] [--label "local Docker"] [--out FILE]

Three measurements per locale:
  1. in-database: faker.benchmark() generates N users in one call (one session)
  2. web path: 10-user batches through psycopg, one after another, as the app does
  3. parallel: K sessions generate disjoint batches at the same time; positions
     are independent, so throughput grows with the number of cores
"""
from __future__ import annotations

import argparse
import os
import platform
import threading
import time
from datetime import date
from pathlib import Path

import psycopg

ROOT = Path(__file__).resolve().parents[1]
URL = os.environ.get("DATABASE_URL", "postgresql://faker:faker@127.0.0.1:5544/faker")


def connect():
    return psycopg.connect(URL, autocommit=True, prepare_threshold=None)


def in_database(locale: str, users: int, text: bool) -> float:
    with connect() as conn:
        row = conn.execute("SELECT seconds, users_per_second FROM faker.benchmark(%s, %s, %s)",
                           (locale, users, text)).fetchone()
    return float(row[1])


def web_batches(locale: str, text: bool, seconds: float = 5.0) -> tuple[float, float]:
    """Sequential 10-user batches over the driver: (users/s, median ms per batch)."""
    times = []
    with connect() as conn:
        conn.execute("SELECT * FROM faker.generate_users(%s, 1, 0, 10, %s)", (locale, text)).fetchall()
        start = time.perf_counter()
        batch = 0
        while time.perf_counter() - start < seconds:
            t = time.perf_counter()
            conn.execute("SELECT * FROM faker.generate_users(%s, 7, %s, 10, %s)", (locale, batch, text)).fetchall()
            times.append(time.perf_counter() - t)
            batch += 1
        elapsed = time.perf_counter() - start
    times.sort()
    return 10 * len(times) / elapsed, 1000 * times[len(times) // 2]


def parallel(locale: str, text: bool, sessions: int, users_per_session: int) -> float:
    """`sessions` connections, each generating its own range of positions."""
    batch_size = 1000
    batches = users_per_session // batch_size
    barrier = threading.Barrier(sessions + 1)
    errors = []

    def worker(n: int):
        try:
            with connect() as conn:
                conn.execute("SELECT count(*) FROM faker.generate_users(%s, 3, 0, 500, %s)", (locale, text))
                barrier.wait()
                for b in range(batches):
                    conn.execute("SELECT sum(length(u::text)) FROM faker.generate_users(%s, 3, %s, %s, %s) u",
                                 (locale, n * batches + b, batch_size, text)).fetchone()
        except Exception as exc:  # report, don't hang the barrier
            errors.append(exc)
            barrier.abort()

    threads = [threading.Thread(target=worker, args=(n,)) for n in range(sessions)]
    for t in threads:
        t.start()
    barrier.wait()
    start = time.perf_counter()
    for t in threads:
        t.join()
    if errors:
        raise errors[0]
    return sessions * batches * batch_size / (time.perf_counter() - start)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--users", type=int, default=100_000)
    ap.add_argument("--text-users", type=int, default=20_000)
    ap.add_argument("--sessions", type=int, default=min(8, os.cpu_count() or 4))
    ap.add_argument("--label", default="local PostgreSQL")
    ap.add_argument("--out", help="also write the Markdown report to this file")
    args = ap.parse_args()

    with connect() as conn:
        version = conn.execute("SHOW server_version").fetchone()[0]
        locales = [r[0] for r in conn.execute("SELECT code FROM faker.list_locales()")]

    rows = []
    for locale in locales:
        for text in (False, True):
            n = args.text_users if text else args.users
            print(f"{locale} text={text}: in-database {n} users ...", flush=True)
            db = in_database(locale, n, text)
            print(f"  {db:,.0f} users/s; web batches ...", flush=True)
            web, ms = web_batches(locale, text)
            print(f"  {web:,.0f} users/s ({ms:.1f} ms per batch); {args.sessions} sessions ...", flush=True)
            par = parallel(locale, text, args.sessions, max(1000, n // args.sessions // 1000 * 1000))
            print(f"  {par:,.0f} users/s", flush=True)
            rows.append((locale, text, n, db, web, ms, par))

    fmt = lambda v: f"{v:,.0f}".replace(",", " ")  # noqa: E731
    lines = [
        "# Benchmark",
        "",
        f"Measured on {date.today().isoformat()}, {args.label}: PostgreSQL {version}, "
        f"client {platform.system()} {platform.machine()}, {os.cpu_count()} logical CPUs. "
        "Run it yourself with `python scripts/benchmark.py`.",
        "",
        "| Locale | Bio text | In-database, 1 session | Web path, batches of 10 | "
        f"{args.sessions} parallel sessions |",
        "| --- | --- | ---: | ---: | ---: |",
    ]
    for locale, text, n, db, web, ms, par in rows:
        lines.append(f"| {locale} | {'yes' if text else 'no'} | **{fmt(db)} users/s** ({fmt(n)} users) "
                     f"| {fmt(web)} users/s, {ms:.1f} ms per batch | {fmt(par)} users/s |")
    lines += [
        "",
        "- **In-database**: `SELECT * FROM faker.benchmark(locale, users, with_text)` generates all users in one "
        "call after a warm-up run and turns every column into text, so no work can be skipped.",
        "- **Web path**: what the app does, one `faker.generate_users(locale, seed, batch, 10)` call per batch "
        "through psycopg, including the network round trip and fetching the rows.",
        "- **Parallel sessions**: every user depends only on (locale, seed, position), so separate sessions can "
        "generate separate ranges of positions with no coordination; throughput grows with CPU cores.",
        "- The Markov chain text costs about 20 index lookups per user (one per word), which is why the "
        "bio column roughly halves the speed.",
    ]
    print("\n".join(lines))
    if args.out:
        Path(args.out).write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
