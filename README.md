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
- [ ] `web/`
- [x] `db-lab/`
- [ ] `sync/`
- [ ] `agent/`
- [ ] `infra/` and CI
- [ ] Final walkthrough notes
