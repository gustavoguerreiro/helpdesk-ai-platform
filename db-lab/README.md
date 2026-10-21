# db-lab: PostgreSQL optimization lab

Small SQL scripts, each with comments explaining the problem and the trade-offs.
Run them in order against a database (a scratch one is fine).

```bash
docker compose up -d                       # from the repository root
export PGURL=postgresql://helpdesk:helpdesk_dev_password@localhost:5432/helpdesk
for f in db-lab/0*.sql; do psql "$PGURL" -v ON_ERROR_STOP=1 -f "$f"; done
```

| Script | Topic | What to show |
|---|---|---|
| `init/01-roles.sql` | Least-privilege roles | `app_user` can read/write, `report_reader` read-only, nobody creates objects in `public` |
| `01_seed_events.sql` | Synthetic data | 500k rows, repeatable |
| `02_index_and_explain.sql` | Composite index | Seq Scan (about 28 ms) to Bitmap Index Scan (about 0.3 ms); equality column first, range column second |
| `03_partitioning.sql` | Range partitioning | Partition pruning in `EXPLAIN`; dropping a partition for retention |
| `04_materialized_view.sql` | Dashboard summary | `REFRESH ... CONCURRENTLY` needs a unique index |
| `05_pg_stat_statements.sql` | Finding slow queries | Measure first, then optimize the top queries |
| `06_expand_and_contract.sql` | Zero-downtime migration | Add column, batched backfill, verify, drop later |
| `07_row_level_security.sql` | Multi-tenant isolation | `SET LOCAL app.team_id` per transaction, safe with PgBouncer |

## What is tested and what is not

Tested: every script ran without errors on PostgreSQL 16.15 (a local server with
`pg_stat_statements` preloaded). The timings above come from that run on a small
machine; yours will differ, the shape of the change is what matters.

Compose stack: verified on 2026-10-21. Scripts 01 to 07 all run against the
`postgres:16` container from `docker-compose.yml`, with `pg_stat_statements` preloaded
through the `command:` line (without it, script 05 fails). The `init/` role script
ran in the container's first-start hook (`app_user` and `report_reader` exist,
neither is superuser nor bypasses RLS).

Not tested here: PgBouncer with `SET LOCAL` end to end (script 07 was run over a
direct connection).

## Trade-offs worth saying out loud

- Indexes speed up reads but cost writes and disk. Add them for measured queries.
- Partitioning adds operational work (creating partitions ahead of time) and
  requires the partition key in the primary key. It pays off for retention and
  time-filtered queries on large tables.
- A materialized view is stale between refreshes. If that is not acceptable,
  maintain an incremental summary table instead.
- RLS is a safety net, not a replacement for application authorization, and it
  does not apply to superusers or owners (this lab uses `FORCE` for the owner).
- A real finding from running the lab: after `SET LOCAL` ends, the setting reads
  as an empty string, not NULL, so the policy uses `NULLIF(..., '')`.
