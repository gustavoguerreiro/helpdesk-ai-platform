# db-lab: PostgreSQL optimization lab

Small SQL scripts, each one answering a real production question: how do I find
what is slow, make it fast, change a schema without downtime, and keep tenants
apart. Every script starts with the **problem it solves**, explains each **step**
in comments, and ends with its **trade-offs**.

Run them in order against a scratch database. They share the `events` table made
by script 01.

```bash
docker compose up -d                       # from the repository root
export PGURL=postgresql://helpdesk:helpdesk_dev_password@localhost:5432/helpdesk
for f in db-lab/0*.sql; do psql "$PGURL" -v ON_ERROR_STOP=1 -f "$f"; done
```

If port 5432 is taken on your machine, start the stack with `POSTGRES_PORT=5433 docker compose up -d`
and use port 5433 in `PGURL`.

## The scripts at a glance

| Script | Problem it solves | What you should see | Main trade-off |
|---|---|---|---|
| `init/01-roles.sql` | The app should not run as superuser or owner | `app_user` (read/write) and `report_reader` (read-only), neither superuser nor `BYPASSRLS` | More roles and secrets to manage |
| `01_seed_events.sql` | Plans only matter on big tables | 500k synthetic events, repeatable | Uniform data is not like real, skewed data |
| `02_index_and_explain.sql` | A query reads the whole table | Seq Scan (~4,000 buffers, ~15 ms) to Bitmap Index Scan (~180 buffers, ~0.3 ms) | Indexes slow writes and use disk |
| `03_partitioning.sql` | Slow deletes and ever-growing tables | `Subplans Removed: 12` (partition pruning); retention by dropping a partition | Primary key must include the partition key; partitions must be created ahead of time |
| `04_materialized_view.sql` | A dashboard scans millions of rows per load | 500k rows become ~55k summary rows, query in under 1 ms | Data is stale between refreshes |
| `05_pg_stat_statements.sql` | "It is slow" does not say which query | Heaviest queries first, by total time | Needs a restart to enable; sees server time only |
| `06_expand_and_contract.sql` | A rename breaks running app instances | `rows_not_backfilled = 0`, with no long lock | Several deploys and temporary double-writing |
| `07_row_level_security.sql` | A forgotten `WHERE` leaks another tenant | 0 rows, then 2 rows for team 1, then 0 again | Safety net only; per-request transaction; policy cost |

The timings come from one run on a small machine (the first run showed about 28 ms
for the sequential scan, a later one about 15 ms). Yours will differ; the shape of
the change is what matters.

## How the pieces connect

```
01 seed events ──► 02 index (same table)
        │
        ├──────► 03 partitioned copy (events_p)
        ├──────► 04 materialized view over events
        ├──────► 05 measure all of the above with pg_stat_statements
        └──────► 06 schema change on a copy (events_demo)

init/01-roles ──► 07 RLS (uses the app_user role)
```

## Reading guide, script by script

**`init/01-roles.sql`: least privilege.** Creates `app_user` and `report_reader`
with `NOBYPASSRLS`, removes `CREATE` on schema `public` for everyone, and sets
default privileges so tables created later get the right grants. Runs once, when
the Docker volume is first created. The superuser stays for migrations only.

**`01_seed_events.sql`.** Builds `events` (500k rows, 50 tenants, 365 days) with
`setseed` so results repeat, then runs `ANALYZE` so the planner has real statistics.

**`02_index_and_explain.sql`.** Shows `EXPLAIN (ANALYZE, BUFFERS)` before and
after `CREATE INDEX CONCURRENTLY ... (tenant_id, created_at)`. Rule to remember:
equality columns first, range column second. Buffers are more stable than time.

**`03_partitioning.sql`.** One parent table, 14 monthly partitions and a default
one. Pruning removes partitions that cannot match the filter. Retention becomes
`DROP` or `DETACH` of the oldest partition, with no mass delete.

**`04_materialized_view.sql`.** Pre-computes daily counts. `REFRESH ... CONCURRENTLY`
keeps readers unblocked but requires a unique index. Something must schedule the
refresh.

**`05_pg_stat_statements.sql`.** Lists queries by total time. Total time finds the
overall cost; mean time finds the individually slow ones. Then use `EXPLAIN`.

**`06_expand_and_contract.sql`.** Add a nullable column, backfill in batches (with
`SKIP LOCKED` and a `COMMIT` per batch), verify, then switch reads and drop the old
column in a later deploy.

**`07_row_level_security.sql`.** A policy compares `team_id` with
`current_setting('app.team_id')`, set per transaction with `SET LOCAL`. Safe by
default: no setting means no rows.

## What is tested and what is not

Tested (2026-10-21): scripts 01 to 07 and `init/01-roles.sql` all run without errors
on PostgreSQL 16 in the `postgres:16` container from `docker-compose.yml`. That
container preloads `pg_stat_statements` through its `command:` line (without it,
script 05 fails). The role script ran in the container's first-start hook:
`app_user` and `report_reader` exist and neither is a superuser or bypasses RLS.

Not tested: `SET LOCAL` through PgBouncer in transaction mode end to end (script
07 ran over a direct connection), partitions created by a scheduled job, a
refresh job for the materialized view, and any of this at production data volume.

## Trade-offs worth saying out loud

- Indexes speed up reads but cost writes and disk. Add them for measured queries.
- Partitioning adds operational work (creating partitions ahead of time) and
  requires the partition key in the primary key. It pays off for retention and
  time-filtered queries on large tables.
- A materialized view is stale between refreshes. If that is not acceptable,
  maintain an incremental summary table instead.
- RLS is a safety net, not a replacement for application authorization, and it
  does not apply to superusers, `BYPASSRLS` roles or owners (this lab uses `FORCE`
  for the owner).
- Expand and contract trades speed for safety: more deploys and temporary
  double-writing, in exchange for no downtime and an easy rollback.
- A real finding from running the lab: after `SET LOCAL` ends, the setting reads
  as an empty string, not NULL, so the policy uses `NULLIF(..., '')`.

## Honest scope

I use PostgreSQL in production, but I have not used Row Level Security in
production. This lab is how I learned it, and it shows what I can demonstrate, not
a claim of production experience.