-- 04 | Materialized view for a dashboard.
--
-- A dashboard that counts events per day, tenant and kind would scan millions of
-- rows on every page load. A materialized view stores the result and is
-- refreshed on a schedule.
--
-- REFRESH ... CONCURRENTLY does not block readers, but it REQUIRES a unique index.

DROP MATERIALIZED VIEW IF EXISTS daily_events;

CREATE MATERIALIZED VIEW daily_events AS
SELECT
  date_trunc('day', created_at) AS day,
  tenant_id,
  kind,
  count(*)                      AS events
FROM events
GROUP BY 1, 2, 3;

-- Required for CONCURRENTLY; also speeds up lookups.
CREATE UNIQUE INDEX daily_events_uq ON daily_events (day, tenant_id, kind);

-- Refresh without blocking readers (run this from a scheduled job).
REFRESH MATERIALIZED VIEW CONCURRENTLY daily_events;

\echo '--- Dashboard query against the view (fast) ---'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF)
SELECT day, sum(events) AS total
FROM daily_events
WHERE tenant_id = 7 AND day >= now() - interval '30 days'
GROUP BY day ORDER BY day;

-- When a full refresh becomes too expensive, switch to an incremental summary
-- table: update only the days that changed instead of recomputing everything.
