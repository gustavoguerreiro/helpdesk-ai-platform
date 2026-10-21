-- 01 | Seed an "events" table with synthetic data.
--
-- Purpose: give the next scripts a table large enough that query plans matter.
-- Safe to re-run: it drops and recreates the table.

DROP TABLE IF EXISTS events CASCADE;

CREATE TABLE events (
  id         BIGSERIAL PRIMARY KEY,
  tenant_id  INT         NOT NULL,   -- which customer the event belongs to
  kind       TEXT        NOT NULL,   -- 'login' | 'sync' | 'error'
  created_at TIMESTAMPTZ NOT NULL,
  payload    JSONB       NOT NULL DEFAULT '{}'
);

-- 500k rows spread across 50 tenants and the last 365 days.
-- setseed makes the random data repeatable, so results are comparable between runs.
SELECT setseed(0.42);
INSERT INTO events (tenant_id, kind, created_at)
SELECT
  1 + floor(random() * 50)::int,
  (ARRAY['login', 'sync', 'error'])[1 + floor(random() * 3)::int],
  now() - (random() * 365) * interval '1 day'
FROM generate_series(1, 500000);

-- Refresh planner statistics so EXPLAIN reflects the real data distribution.
ANALYZE events;

SELECT count(*) AS rows_seeded FROM events;
