# sync: incremental, idempotent data feed

**Problem.** Keep a PostgreSQL table up to date from an external source
(for example Snowflake) without copying everything every time, and without
losing or duplicating rows when a run fails halfway.

The source here is a simulated in-memory `FakeSource` so the project runs without
credentials. A real source only has to implement `fetch_changed(after_updated, after_id, limit)`.

## How it works

1. **Cursor.** `sync_state` stores `(last_updated, last_id)`. Ordering by both
   columns makes the cursor exact even when many rows share a timestamp.
2. **Batch.** Fetch the next N rows after the cursor, oldest first.
3. **One transaction per batch.** Load into a temp staging table, upsert with
   `INSERT ... ON CONFLICT DO UPDATE`, and move the cursor. All or nothing.
4. **Guard.** The upsert only overwrites a row if the incoming `updated_at` is newer.
5. **Freshness.** `check_freshness` compares the cursor with now; the CLI exits
   non-zero when the lag exceeds the limit, which is what an alert would watch.

## Run

```bash
pip install -r sync/requirements.txt
cd sync && python sync.py                 # demo run (needs the Postgres from docker compose)
cd .. && pytest sync -q                   # tests (set TEST_DATABASE_URL to any Postgres)
```

## What is tested and what is only an example

Tested (7 tests, on PostgreSQL 16): first run in batches, second run does nothing,
only changed rows are picked up, many rows with the same timestamp, replaying an
old row does not overwrite a newer one, a failed batch leaves the cursor
unchanged, the freshness check.

Only an example: the Snowflake side (simulated), scheduling (in production this
would be an Airflow/Dagster task or an Azure scheduled job), and alert wiring.

## Trade-offs

- The cursor catches rows whose `updated_at` moves forward. Rows that appear in
  the source late with an *older* timestamp are missed. A common fix is to start
  each run slightly before the cursor (a lookback window); the idempotent upsert
  makes that safe.
- Hard deletes in the source are invisible to this approach. Use a soft-delete
  flag or a periodic reconciliation (compare counts or ids).
- Moving the cursor in the same transaction as the data is simpler and safer than
  "advance after commit" in a separate step, because there is no gap between them.
