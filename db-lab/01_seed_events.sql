-- 01 | Seed an "events" table with synthetic data.
--
-- PROBLEM THIS SOLVES
--   Query plans only get interesting when a table is big. On 100 rows Postgres
--   always reads everything and no index matters. The next scripts (index,
--   partitioning, materialized view, pg_stat_statements) need a table with
--   enough rows to show real differences, and the same data every time so
--   results can be compared between runs.
--
-- WHAT YOU SHOULD SEE
--   "rows_seeded = 500000" at the end.
--
-- Safe to re-run: it drops and recreates the table.

-- Step 1: start clean. CASCADE also drops things that depend on the table
-- (for example a view created from it in an earlier run).
DROP TABLE IF EXISTS events CASCADE;

-- Step 2: the table. It looks like a typical multi-tenant activity log.
CREATE TABLE events (
  id         BIGSERIAL PRIMARY KEY,
  tenant_id  INT         NOT NULL,   -- which customer the event belongs to
  kind       TEXT        NOT NULL,   -- 'login' | 'sync' | 'error'
  created_at TIMESTAMPTZ NOT NULL,
  payload    JSONB       NOT NULL DEFAULT '{}'
);

-- Step 3: fill it with 500k rows spread across 50 tenants and the last 365 days.
-- setseed makes the random data repeatable, so results are comparable between runs.
SELECT setseed(0.42);
INSERT INTO events (tenant_id, kind, created_at)
SELECT
  1 + floor(random() * 50)::int,
  (ARRAY['login', 'sync', 'error'])[1 + floor(random() * 3)::int],
  now() - (random() * 365) * interval '1 day'
FROM generate_series(1, 500000);

-- Step 4: refresh planner statistics so EXPLAIN reflects the real data distribution.
-- Without ANALYZE the planner works with stale guesses and may pick a bad plan.
ANALYZE events;

SELECT count(*) AS rows_seeded FROM events;

-- TRADE-OFFS
--   * Synthetic data is uniform (every tenant has about the same volume). Real
--     data is skewed (a few huge tenants), which changes plans and makes
--     per-tenant indexes behave differently. Treat the numbers as a shape, not a
--     benchmark.
--   * setseed is repeatable for this one session; the order rows land on disk can
--     still vary slightly between runs.
--   * The first 365 days are "now minus random", so the data drifts as time
--     passes. Re-run the script to refresh it.
