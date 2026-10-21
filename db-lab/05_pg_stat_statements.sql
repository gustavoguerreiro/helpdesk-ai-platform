-- 05 | Finding slow queries with pg_stat_statements.
--
-- PROBLEM THIS SOLVES
--   "The app is slow" does not say which query to fix. Optimizing by guesswork
--   wastes time on queries that do not matter. pg_stat_statements records, for
--   every distinct query, how many times it ran and how long it took, so you
--   optimize the queries that cost the most overall.
--
-- WHAT YOU SHOULD SEE
--   A table with the heaviest queries first. Here the JSON containment query and
--   the GROUP BY (both full scans) cost far more than the indexed query from
--   script 02. Literal values appear as $1: the extension groups queries that
--   differ only by their parameters.
--
-- REQUIREMENT
--   shared_preload_libraries = 'pg_stat_statements' in the server config, and a
--   restart. docker-compose.yml sets it with the "command:" line. Without it,
--   the SELECT below fails with "must be loaded via shared_preload_libraries".

-- Step 1: enable the extension in this database and clear old statistics, so we
-- only look at the workload of this run.
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
SELECT pg_stat_statements_reset();

-- Step 2: generate some workload so there is something to look at.
SELECT count(*) FROM events WHERE tenant_id = 7 AND created_at >= now() - interval '7 days';
SELECT kind, count(*) FROM events GROUP BY kind;
SELECT count(*) FROM events WHERE payload @> '{"a": 1}';

-- Step 3: list the top queries by total execution time.
\echo '--- Top queries by total time (the ones worth optimizing first) ---'
SELECT
  calls,
  round(total_exec_time::numeric, 2) AS total_ms,
  round(mean_exec_time::numeric, 2)  AS mean_ms,
  rows,
  left(regexp_replace(query, '\s+', ' ', 'g'), 80) AS query
FROM pg_stat_statements
WHERE query NOT ILIKE '%pg_stat_statements%'
ORDER BY total_exec_time DESC
LIMIT 5;

-- Step 4: read the result.
--   High total_ms = most cost overall (often a cheap query called very often).
--   High mean_ms  = individually slow.
-- Then run EXPLAIN (ANALYZE, BUFFERS) on those queries and decide on an index,
-- a rewrite, or caching. Measure again after the change.

-- TRADE-OFFS
--   * Needs a server restart to turn on (shared_preload_libraries), and costs a
--     little memory and CPU. Managed services (Azure Flexible Server) offer it as
--     a server parameter.
--   * It measures time inside the server only. It does not see network time,
--     pool wait time (PgBouncer) or time spent in the application.
--   * Statistics are cumulative since the last reset, so a query that was slow
--     last month can still rank high. Reset or compare snapshots over time.
--   * It stores normalized text, not the individual parameter values, so it
--     cannot tell you WHICH tenant made a slow call. Use logs for that.
--   * Total time and mean time answer different questions. Look at both.
