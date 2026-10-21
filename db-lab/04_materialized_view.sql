-- 04 | Materialized view for a dashboard.
--
-- PROBLEM THIS SOLVES
--   A dashboard that counts events per day, tenant and kind would scan millions
--   of rows on every page load. A materialized view stores the result of that
--   query on disk, so the dashboard reads a small pre-computed table, and the
--   expensive work happens on a schedule instead of on every request.
--
-- WHAT YOU SHOULD SEE
--   * 500,000 events collapse into about 55,000 summary rows.
--   * The dashboard query reads about 90 rows through the index in under 1 ms.
--
-- REFRESH ... CONCURRENTLY does not block readers, but it REQUIRES a unique index.

-- Step 1: start clean.
DROP MATERIALIZED VIEW IF EXISTS daily_events;

-- Step 2: create the view. Unlike a normal view, the result is stored on disk and
-- does not change until it is refreshed.
CREATE MATERIALIZED VIEW daily_events AS
SELECT
  date_trunc('day', created_at) AS day,
  tenant_id,
  kind,
  count(*)                      AS events
FROM events
GROUP BY 1, 2, 3;

-- Step 3: a unique index. Required for CONCURRENTLY: Postgres compares the new
-- result with the old one row by row (by this key) and applies only the
-- differences. It also speeds up lookups.
CREATE UNIQUE INDEX daily_events_uq ON daily_events (day, tenant_id, kind);

-- Step 4: refresh without blocking readers (run this from a scheduled job).
-- A plain REFRESH would lock the view against reads while it recomputes.
REFRESH MATERIALIZED VIEW CONCURRENTLY daily_events;

-- Step 5: the dashboard query, now against the small table.
\echo '--- Dashboard query against the view (fast) ---'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF)
SELECT day, sum(events) AS total
FROM daily_events
WHERE tenant_id = 7 AND day >= now() - interval '30 days'
GROUP BY day ORDER BY day;

-- When a full refresh becomes too expensive, switch to an incremental summary
-- table: update only the days that changed instead of recomputing everything.

-- TRADE-OFFS
--   * Staleness: the data is only as fresh as the last refresh. If a dashboard
--     needs near real time, use an incremental summary table (upsert only the
--     changed days) or query the base table with an index.
--   * A refresh recomputes EVERYTHING. With millions of rows and frequent
--     refreshes the cost adds up. CONCURRENTLY is also slower than a plain
--     refresh and needs temporary space.
--   * Nobody refreshes it for you. In production a scheduled job (Airflow, a
--     Container Apps Job, or pg_cron) must run the REFRESH and be monitored.
--   * Index column order: this index is (day, tenant_id, kind), but the dashboard
--     filters tenant_id by equality and day by range. By the rule in script 02,
--     (tenant_id, day, kind) would be a better fit for this query. Uniqueness
--     holds with either order; only read efficiency changes.
--   * Row Level Security cannot be applied to a materialized view, so tenant
--     filtering must be done in the query or a wrapper view.
