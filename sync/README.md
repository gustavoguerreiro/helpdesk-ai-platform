# sync: incremental, idempotent data feed

**Problem.** Keep a PostgreSQL table up to date from an external source (for example
Snowflake) without copying everything every time, and without losing or duplicating
rows when a run fails halfway.

The source here is a simulated in-memory `FakeSource`, so the project runs without
credentials. A real source only has to implement
`fetch_changed(after_updated, after_id, limit)`.

## How it works

Three pieces hold each other up:

1. **A cursor** `(updated_at, id)` stored in `sync_state`. Ordering by both columns
   makes it exact even when many rows share a timestamp.
2. **An idempotent upsert** (`INSERT ... ON CONFLICT DO UPDATE`) guarded so it never
   replaces a row with an older version. Replaying a batch changes nothing.
3. **The cursor moves in the same transaction as the data.** Either both are saved
   or neither is.

```
        ┌──────────────────────────────── repeat until the source has nothing newer
        │
 read cursor ──► fetch next N rows after it ──► BEGIN
 (sync_state)     (source.fetch_changed)          load staging table (TEMP)
                                                  upsert into customers (guarded)
                                                  move cursor to the last row
                                                COMMIT
                                    failure anywhere ──► ROLLBACK: cursor unchanged,
                                                         the next run retries the batch
```

Why the single transaction matters:

| Cursor moves... | Crash between the two writes | Result |
|---|---|---|
| before the data, separate commit | cursor advanced, data missing | rows lost silently |
| after the data, separate commit | data saved, cursor behind | batch reprocessed (harmless, thanks to the upsert) |
| in the same transaction | nothing saved | batch reprocessed |

## Files

| File | What it is |
|---|---|
| `schema.sql` | `customers` (destination) and `sync_state` (one cursor row per feed) |
| `source.py` | `FakeSource` and the one method a real source must provide |
| `sync.py` | The engine: `read_cursor`, `apply_batch`, `run_sync`, `check_freshness`, plus a demo `__main__` |
| `tests/test_sync.py` | 7 tests that act as the specification |

## Presenting it, file by file

About 5 minutes. For each file: open it, say the point, show the evidence.

### 1. `schema.sql` (30 seconds)
- **Open:** the `sync_state` table.
- **Point:** the cursor is two columns, `last_updated` and `last_id`, starting at
  `'epoch'` and `0`, so the first run reads everything with no special case. One row
  per feed. `customers.synced_at` records when this system wrote the row, which helps
  debugging; `updated_at` is what the source reports.

### 2. `source.py` (45 seconds)
- **Open:** `fetch_changed`.
- **Point:** this is the whole contract with the source: rows strictly after the cursor,
  ordered, at most N. The tuple comparison `(updated_at, id) > (cursor_updated, cursor_id)`
  is what makes the cursor exact. With `updated_at` alone, a batch cut in the middle of
  rows that share a timestamp would skip or repeat them. For Snowflake the same idea is
  `WHERE updated_at > x OR (updated_at = x AND id > y) ORDER BY updated_at, id LIMIT n`.
  The Snowflake side is simulated and was not run.

### 3. `sync.py` (2 minutes, the core)
Walk the functions in the order the data flows:
1. **`read_cursor`:** creates the state row on the first run, then reads it.
2. **`run_sync`:** the loop. Read cursor, `commit` to end the read, fetch a batch, stop on
   an empty batch, apply, `commit`. On any error: `rollback` and re-raise.
3. **`apply_batch`:** three statements, one transaction.
   - Staging: a `TEMP` table (private to the transaction, dropped at commit) so the batch
     is upserted with one statement instead of one round trip per row.
   - Upsert with `WHERE customers.updated_at < EXCLUDED.updated_at`: the guard against
     writing an older version over a newer one.
   - Cursor update to the last row of the batch.
4. **`check_freshness`:** lag is now minus the cursor. The CLI exits non-zero when the
   lag is over the limit, which is what an alert would watch.

**Show:**

```bash
export DATABASE_DIRECT_URL=postgresql://helpdesk:helpdesk_dev_password@localhost:5432/helpdesk
cd sync && python sync.py
```

Expected: `batches=3 rows=2500 fresh=True ...`. Then in `psql`: `SELECT * FROM sync_state;`
shows the cursor at the newest row. Running the demo a second time reads some rows again
because the demo regenerates its fake rows with the current time on every run, so their
timestamps differ. That is a property of the demo data; the tests below show the real
behavior (a second run reads nothing).

### 4. `tests/test_sync.py` (1.5 minutes)
Run `pytest sync -v` (set `TEST_DATABASE_URL`). Then show two tests:
- **`test_many_rows_with_the_same_timestamp_are_not_lost`:** 30 rows share one timestamp,
  the batch size is 7. This is the test that proves the `id` tie-breaker.
- **`test_failed_batch_leaves_cursor_unchanged`:** a `NULL` in a `NOT NULL` column makes the
  batch fail; the cursor stays at 0, so the next run retries it. This is the test that proves
  the single transaction.

| Test | What it proves |
|---|---|
| first run copies everything in batches | 25 rows, batch size 10, gives 3 batches |
| second run is a no-op | nothing new, nothing written |
| only changed rows are picked up | one changed row, updated in place, no duplicate |
| many rows with the same timestamp | the `(updated_at, id)` cursor loses nothing |
| replaying an old row | the guard never overwrites a newer version |
| failed batch leaves cursor unchanged | data and cursor are atomic |
| freshness check | passes inside the limit, fails outside |

Each test creates and drops its own schema, so tests do not affect each other. Without
a reachable Postgres the tests are skipped.

## Run

```bash
pip install -r sync/requirements.txt
# demo (needs the Postgres from docker compose; set the direct URL, see .env.example)
cd sync && python sync.py
# tests (any Postgres)
cd .. && TEST_DATABASE_URL=postgresql://helpdesk:helpdesk_dev_password@localhost:5432/lab_test pytest sync -q
```

If port 5432 is taken, start the stack with `POSTGRES_PORT=5433 docker compose up -d` and
use 5433 in the URLs.

## What is tested and what is only an example

Tested (7 tests, PostgreSQL 16, also run in CI): first run in batches, second run does
nothing, only changed rows are picked up, many rows with the same timestamp, replaying an
old row does not overwrite a newer one, a failed batch leaves the cursor unchanged, the
freshness check. The demo (`python sync.py`) was run against the compose Postgres.

Only an example: the Snowflake side (simulated), retries and scheduling (in production an
Airflow task or an Azure Container Apps Job would call `run_sync` and retry on failure),
and alert wiring.

## Known limits

- **Hard deletes in the source are invisible.** The cursor only sees rows whose
  `updated_at` moves. Use a soft-delete flag, a tombstone table, or a periodic
  reconciliation (compare ids or counts).
- **Late rows are missed.** A row that appears in the source with an `updated_at` older
  than the cursor is skipped. Start each run slightly before the cursor (an overlap
  window); the idempotent upsert makes that safe.
- **Same timestamp, new content.** The guard uses a strict `<`, so an update that keeps the
  same `updated_at` is ignored (read from the SQL; there is no test for it).
- **Freshness is measured against the clock.** If the source simply has no new data, lag
  grows and the alert fires. Compare with the source's own newest timestamp instead.
- **Row by row staging.** `executemany` sends one row at a time; at real volume use `COPY`.
- **One feed.** The feed name, table and columns are fixed in the code. Several tables need
  the table and column list to be configuration, plus one cursor row per table.

## Trade-offs

- Moving the cursor in the same transaction as the data is simpler and safer than advancing
  it afterwards in a separate step, because there is no gap between the two writes.
- One transaction per batch bounds the size of a rollback and the time locks are held, at
  the cost of more commits than one big transaction.
- A keyset cursor stays fast on large tables and is exact with ties, but it cannot jump to
  an arbitrary position and depends on a trustworthy `updated_at` in the source.
- Idempotence makes retries trivial, but it means correctness depends on the upsert key
  and the guard, so those need tests (they have them).
