-- 02 | Indexes and EXPLAIN.
--
-- Question: "how many events did tenant 7 have in the last 7 days?"
-- Without an index, Postgres must read the whole table (a sequential scan).
-- With a composite index it can jump to the matching rows.
--
-- Column order in a composite index matters: equality columns first
-- (tenant_id), then the range column (created_at).

DROP INDEX IF EXISTS events_tenant_created_idx;

\echo '--- BEFORE the index (expect: Seq Scan) ---'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF)
SELECT count(*) FROM events
WHERE tenant_id = 7 AND created_at >= now() - interval '7 days';

-- On a big, live table in production use CREATE INDEX CONCURRENTLY, which does
-- not block writes. It cannot run inside a transaction block, so this script
-- (run with psql, one statement at a time) is a valid place for it.
CREATE INDEX CONCURRENTLY events_tenant_created_idx
  ON events (tenant_id, created_at);
ANALYZE events;

\echo '--- AFTER the index (expect: Bitmap Index Scan, far fewer buffers and milliseconds) ---'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF)
SELECT count(*) FROM events
WHERE tenant_id = 7 AND created_at >= now() - interval '7 days';
