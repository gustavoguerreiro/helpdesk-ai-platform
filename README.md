# helpdesk-ai-platform

A small, runnable **demonstration project** that shows how I would approach a typical
set of platform problems: a Next.js + Prisma web app, PostgreSQL schema optimization,
an incremental and idempotent data feed, an AI agent with permission-aware tools and
human approval, and infrastructure-as-code basics.

> **Honest scope note.** This is a learning and demonstration project, built to show
> my reasoning and the patterns I would use. It is not a production system, and I am
> not claiming production experience with every tool in it (for example Prisma, Bicep
> and Azure). Each folder says what is tested and what is only an example.

## Repository map

| Folder | What it demonstrates | Stack |
|---|---|---|
| [`web/`](web/) | Server components, route handlers, Server Actions, Prisma schema and migrations, input validation | Next.js (App Router), TypeScript, Prisma |
| [`db-lab/`](db-lab/) | Indexes and `EXPLAIN`, time partitioning, materialized views, zero-downtime migrations, least-privilege roles | PostgreSQL 16, SQL |
| [`sync/`](sync/) | Incremental feed with a watermark, idempotent upserts, freshness check | Python, PostgreSQL |
| [`agent/`](agent/) | Tool-calling loop, per-user permissions (RBAC), human approval gate, cost/step logging, tests with a fake model | Python, FastAPI, pytest |
| [`infra/`](infra/) | Declarative infrastructure example and a CI workflow | Bicep, GitHub Actions |
| [`docs/`](docs/) | Architecture notes and decisions | Markdown |

## Local environment

```bash
cp .env.example .env
docker compose up -d        # PostgreSQL on :5432, PgBouncer on :6432
# Port 5432 already taken? POSTGRES_PORT=5433 docker compose up -d
#   (then use :5433 in DATABASE_DIRECT_URL and TEST_DATABASE_URL)
```

PostgreSQL is exposed directly on port 5432 (used for migrations and the SQL lab).
PgBouncer is on port 6432 (used by the app at runtime, in transaction pooling mode).

## How to read this repository

Every source file starts with a short comment explaining what it is for, and each
non-obvious step is commented in English. Each folder has its own README with:

1. what problem it addresses,
2. how to run it,
3. what is tested and what is only an example,
4. the main trade-offs.

## Status

- [x] Repository base and local environment
- [x] `web/` (migrate, seed, typecheck, tests, build and the running app were verified, see its README)
- [x] `db-lab/`
- [x] `sync/`
- [x] `agent/`
- [x] `infra/` and CI (Bicep compiles; never deployed)
- [x] Final walkthrough notes ([docs/walkthrough.md](docs/walkthrough.md))

## Verification summary (what was actually run, 2026-10-21)

| Area | Result |
|---|---|
| `db-lab/` | Scripts 01 to 07 and the role script ran on PostgreSQL 16 (the compose container) |
| `sync/` | 7 tests passed against PostgreSQL 16; demo run against the compose database; also run in CI |
| `agent/` | 14 tests passed (fake model); the real-model adapter was never run |
| `web/` | `prisma migrate`, seed, typecheck, 7 tests, `next build`, the running app through PgBouncer and the forms in a browser; no authentication or authorization yet (see its README) |
| `infra/` | `az bicep build` succeeds (also in CI); nothing was deployed to Azure |
| `docker-compose.yml` | PostgreSQL 16 and PgBouncer (transaction mode) run; `pg_stat_statements` preloaded |
| CI | `python`, `web` and `bicep` jobs pass on GitHub Actions |
