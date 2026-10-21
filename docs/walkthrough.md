# Presentation walkthrough

Suggested order, about 2 minutes per part. Open the folder's README, then one or
two files. Say what the problem is before showing the code.

## 1. `db-lab/` (PostgreSQL)
- Run `02_index_and_explain.sql`. Show the plan change from a sequential scan (about 28 ms) to a bitmap index scan (about 0.3 ms). Point out the column order of the composite index (equality first, range second).
- Mention partitioning (`03`) for retention, `REFRESH ... CONCURRENTLY` needing a unique index (`04`), `pg_stat_statements` to find what to optimize (`05`).
- `07_row_level_security.sql`: `SET LOCAL app.team_id` per transaction, which is safe with PgBouncer transaction mode. The empty-string detail (`NULLIF`) is a real thing I hit while testing.

## 2. `web/` (Next.js + Prisma)
- `prisma/schema.prisma`: indexes, and `url` vs `directUrl` for PgBouncer.
- `lib/prisma.ts`: why a singleton. `app/actions.ts`: Server Action validating input and calling `revalidatePath`.
- `app/api/tickets/route.ts`: cursor pagination. Be upfront that Prisma was not run in my sandbox (see `web/README.md`).

## 3. `sync/` (incremental feed)
- Keyset cursor `(updated_at, id)`, one transaction per batch, upsert guard against older versions, freshness check.
- Open `tests/test_sync.py`: "many rows with the same timestamp" and "failed batch leaves cursor unchanged".

## 4. `agent/` (AI agent)
- Draw the layers from `agent/README.md`: validation, RBAC, data scoping, approval gate, step limit, audit log.
- Show `test_forbidden_tool_is_blocked_and_audited` and `test_approval_gate_queues_instead_of_executing`.
- Say clearly: the real-model adapter was not run, tests use a scripted fake model.

## 5. `infra/` and CI
- Bicep Key Vault + Log Analytics as an example of the pattern; CI runs tests, Prisma generate/build and `az bicep build`.
