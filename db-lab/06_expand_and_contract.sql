-- 06 | Zero-downtime schema change: "expand and contract".
--
-- Goal: rename events.kind to events.event_kind without breaking the running app.
-- A direct RENAME would break every deployed instance that still uses the old
-- name. Instead, change the schema in compatible steps across several deploys.
--
--   Step 1 (expand)   add the new column, nullable, no default rewrite
--   Step 2            app writes BOTH columns; backfill old rows in small batches
--   Step 3            app reads from the new column
--   Step 4 (contract) stop writing the old column, then drop it
--
-- Each step is safe to roll back, because the old column still exists until the end.

-- Use a copy so the other scripts are not affected.
DROP TABLE IF EXISTS events_demo;
CREATE TABLE events_demo AS SELECT id, tenant_id, kind, created_at FROM events LIMIT 100000;
ALTER TABLE events_demo ADD PRIMARY KEY (id);

-- Step 1: expand. Adding a nullable column without a default is instant.
ALTER TABLE events_demo ADD COLUMN event_kind TEXT;

-- Step 2: backfill in batches so locks are short and replicas do not lag.
-- Repeat until it updates 0 rows. It is idempotent: re-running is harmless.
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

-- Verify nothing is left behind before moving to step 3.
SELECT count(*) AS rows_not_backfilled FROM events_demo WHERE event_kind IS NULL;

-- Step 4 (contract), after every app version uses the new column:
-- ALTER TABLE events_demo DROP COLUMN kind;
