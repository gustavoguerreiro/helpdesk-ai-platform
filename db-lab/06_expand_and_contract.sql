-- 06 | Zero-downtime schema change: "expand and contract".
--
-- PROBLEM THIS SOLVES
--   We want to rename events.kind to events.event_kind while the app is running.
--   A direct RENAME would break every deployed instance that still uses the old
--   name: during a rolling deploy, old and new app versions run at the same time.
--   Instead, change the schema in compatible steps across several deploys.
--
--   Step 1 (expand)   add the new column, nullable, no default rewrite
--   Step 2            app writes BOTH columns; backfill old rows in small batches
--   Step 3            app reads from the new column
--   Step 4 (contract) stop writing the old column, then drop it
--
-- Each step is safe to roll back, because the old column still exists until the end.
--
-- WHAT YOU SHOULD SEE
--   "rows_not_backfilled = 0": every old row has the new column filled in.
--   Only steps 1 and 2 are executed here; the app-side steps (writing both
--   columns, switching reads) happen in application code, and the final DROP is
--   left commented on purpose.

-- Step 0: work on a copy so the other scripts are not affected.
DROP TABLE IF EXISTS events_demo;
CREATE TABLE events_demo AS SELECT id, tenant_id, kind, created_at FROM events LIMIT 100000;
ALTER TABLE events_demo ADD PRIMARY KEY (id);

-- Step 1: expand. Adding a nullable column without a default is instant: Postgres
-- only changes the catalog and does not rewrite the table.
ALTER TABLE events_demo ADD COLUMN event_kind TEXT;

-- Step 2: backfill in batches so locks are short and replicas do not lag.
-- Repeat until it updates 0 rows. It is idempotent: re-running is harmless.
--   * LIMIT 20000      each batch touches a bounded number of rows
--   * FOR UPDATE SKIP LOCKED  skip rows another transaction holds, do not wait
--   * COMMIT           releases locks between batches (allowed in a DO block that
--                      is not inside an outer transaction)
DO $$
DECLARE
  updated int;
BEGIN
  LOOP
    UPDATE events_demo
    SET event_kind = kind
    WHERE id IN (
      SELECT id FROM events_demo
      WHERE event_kind IS NULL
      ORDER BY id
      LIMIT 20000
      FOR UPDATE SKIP LOCKED
    );
    GET DIAGNOSTICS updated = ROW_COUNT;
    EXIT WHEN updated = 0;
    COMMIT;  -- release locks between batches (allowed in a DO block outside a transaction)
  END LOOP;
END $$;

-- Step 3: verify nothing is left behind before the app switches its reads.
SELECT count(*) AS rows_not_backfilled FROM events_demo WHERE event_kind IS NULL;

-- Step 4 (contract), after every app version uses the new column:
-- ALTER TABLE events_demo DROP COLUMN kind;

-- TRADE-OFFS
--   * More work: several deploys instead of one, plus temporary code that writes
--     both columns. That is the price of no downtime.
--   * Rows inserted during the backfill have event_kind NULL unless the app (step
--     2) or a trigger writes both columns. That is why step 2 exists.
--   * The backfill is slower than one big UPDATE and creates dead rows, so
--     VACUUM has work to do afterwards. Small batches mean short locks but a
--     longer total time.
--   * One UPDATE of tens of millions of rows holds locks for a long time, writes
--     a huge amount of WAL, can make replicas lag and bloats the table.
--   * ADD COLUMN with a constant DEFAULT is fast since Postgres 11, but adding a
--     NOT NULL constraint or a volatile default can still scan or rewrite the
--     table. Add the constraint with NOT VALID, then VALIDATE it separately.
--   * Prisma Migrate applies generated SQL in one go. It does not do this
--     pattern for you; you write the steps (and the batched backfill) yourself.
