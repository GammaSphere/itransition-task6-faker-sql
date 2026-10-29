# Benchmark

Speed of fake user generation, measured on 2026-10-29 with `python scripts/benchmark.py`. The headline figure is the **in-database, single session** column: `faker.benchmark()` generating users inside PostgreSQL.

## Local PostgreSQL

PostgreSQL 17.11 in a Docker container (`docker compose up`) on a Windows 11 desktop with 32 logical CPUs; the client runs on the same machine.

| Locale | Bio text | In-database, 1 session | Web path, batches of 10 | 8 parallel sessions |
| --- | --- | ---: | ---: | ---: |
| en_US | no | **8 332 users/s** (100 000 users) | 4 129 users/s, 2.3 ms per batch | 50 809 users/s |
| en_US | yes | **4 068 users/s** (20 000 users) | 2 458 users/s, 4.0 ms per batch | 25 286 users/s |
| de_DE | no | **9 428 users/s** (100 000 users) | 4 504 users/s, 2.1 ms per batch | 55 734 users/s |
| de_DE | yes | **4 155 users/s** (20 000 users) | 2 703 users/s, 3.6 ms per batch | 24 943 users/s |

## Deployed database: Neon free tier

PostgreSQL 18.6 on Neon (aws-eu-central-1, free plan with autoscaling compute). The client was the same development machine, connecting over the internet, so the web-path column here is dominated by the network round trip; the deployed app runs in Vercel's Frankfurt region next to the database.

| Locale | Bio text | In-database, 1 session | Web path, batches of 10 | 4 parallel sessions |
| --- | --- | ---: | ---: | ---: |
| en_US | no | **7 236 users/s** (100 000 users) | 121 users/s, 81.8 ms per batch | 6 062 users/s |
| en_US | yes | **2 777 users/s** (20 000 users) | 119 users/s, 83.6 ms per batch | 2 492 users/s |
| de_DE | no | **7 269 users/s** (100 000 users) | 111 users/s, 88.7 ms per batch | 6 380 users/s |
| de_DE | yes | **2 729 users/s** (20 000 users) | 119 users/s, 83.9 ms per batch | 2 511 users/s |

The free Neon compute has a fraction of one CPU, so parallel sessions do not add throughput there.

## What the columns measure

- **In-database, 1 session**: `SELECT * FROM faker.benchmark(locale, users, with_text)` runs a warm-up batch, then generates all users in one `generate_users` call, turns every column of every row into text (so the planner cannot skip work) and divides by the elapsed time.
- **Web path**: what the app does, one `faker.generate_users(locale, seed, batch, 10)` call per batch through psycopg, including the round trip and fetching the rows.
- **Parallel sessions**: every user depends only on (locale, seed, position), so separate sessions can generate separate ranges of positions with no coordination. On a multi-core server throughput grows with the number of cores.
- **Bio text** costs about one index lookup per generated word (around 20 per user), which is why it roughly halves the speed.

Run `SELECT * FROM faker.benchmark('en_US', 100000);` on any installation to reproduce the in-database figure, or use the Benchmark page of the app for a quick run on the deployed database.
