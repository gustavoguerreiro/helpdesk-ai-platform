-- Tables used by the incremental sync.
-- Every statement is idempotent (IF NOT EXISTS), so running it twice is harmless.

-- The destination table: a copy of the source "customers" data.
CREATE TABLE IF NOT EXISTS customers (
  id         BIGINT      PRIMARY KEY,   -- same id as in the source
  name       TEXT        NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,      -- last change time, as reported by the source
  synced_at  TIMESTAMPTZ NOT NULL DEFAULT now()  -- when WE last wrote this row
);

-- Where the last successful run stopped. One row per feed.
-- The pair (updated_at, id) is a "keyset" cursor: ordering by both makes it
-- unambiguous even when many rows share the same timestamp.
CREATE TABLE IF NOT EXISTS sync_state (
  feed          TEXT        PRIMARY KEY,
  last_updated  TIMESTAMPTZ NOT NULL DEFAULT 'epoch',
  last_id       BIGINT      NOT NULL DEFAULT 0,
  last_run_at   TIMESTAMPTZ
);
