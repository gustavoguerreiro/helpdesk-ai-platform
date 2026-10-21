-- 05 | Finding slow queries with pg_stat_statements.
--
-- Requires shared_preload_libraries = 'pg_stat_statements' (set in the server
-- config, needs a restart). The extension then records per-query statistics.
-- Do not guess what is slow: measure it.

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
SELECT pg_stat_statements_reset();

-- Generate some workload so there is something to look at.
SELECT count(*) FROM events WHERE tenant_id = 7 AND created_at >= now() - interval '7 days';
SELECT kind, count(*) FROM events GROUP BY kind;
SELECT count(*) FROM events WHERE payload @> '{"a": 1}';

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

-- Reading it: high total_ms = most cost overall (often a cheap query called
-- very often). High mean_ms = individually slow. Then run EXPLAIN on those.
