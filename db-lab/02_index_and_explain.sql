-- 02 | Indexes and EXPLAIN.
--
-- PROBLEM THIS SOLVES
--   "How many events did tenant 7 have in the last 7 days?" returns 181 rows out
--   of 500,000, but without an index Postgres reads the whole table to find
--   them (a sequential scan). That is slow, and it gets slower as the table
--   grows. This script shows how to prove the problem with EXPLAIN and fix it
--   with a composite index.
--
-- WHAT YOU SHOULD SEE (numbers vary by machine; the shape is what matters)
--   BEFORE: Parallel Seq Scan, about 4,000 buffers, about 15 ms
--   AFTER : Bitmap Index Scan + Bitmap Heap Scan, about 180 buffers, about 0.3 ms
--
-- How to read EXPLAIN (ANALYZE, BUFFERS):
--   Seq Scan              reads every page of the table
--   Rows Removed by Filter rows read and thrown away (a sign an index could help)
--   Bitmap Index Scan     finds matching row locations in the index
--   Bitmap Heap Scan      visits those table pages once each, in physical order
--   Buffers shared hit    pages found in cache; "read" means they came from disk
--   Execution Time        the real time; Buffers is more stable between runs

-- Step 1: remove the index if an earlier run created it, so BEFORE is honest.
DROP INDEX IF EXISTS events_tenant_created_idx;

-- Step 2: measure BEFORE. EXPLAIN ANALYZE really runs the query and reports actuals.
\echo '--- BEFORE the index (expect: Seq Scan) ---'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF)
SELECT count(*) FROM events
WHERE tenant_id = 7 AND created_at >= now() - interval '7 days';

-- Step 3: create the index.
-- Column order matters: equality column first (tenant_id), range column second
-- (created_at). The index is sorted by tenant, then by date inside each tenant,
-- so the search jumps to tenant 7 and reads one contiguous range of dates.
-- (created_at, tenant_id) would find the 7-day range first and then filter by
-- tenant inside it, reading many useless entries.
--
-- On a big, live table in production use CREATE INDEX CONCURRENTLY: it does not
-- block writes. It cannot run inside a transaction block, so this script (run
-- with psql, one statement at a time) is a valid place for it.
CREATE INDEX CONCURRENTLY events_tenant_created_idx
  ON events (tenant_id, created_at);

-- Step 4: refresh table statistics so the planner starts from fresh numbers.
ANALYZE events;

-- Step 5: measure AFTER with the exact same query.
\echo '--- AFTER the index (expect: Bitmap Index Scan, far fewer buffers and milliseconds) ---'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF)
SELECT count(*) FROM events
WHERE tenant_id = 7 AND created_at >= now() - interval '7 days';

-- TRADE-OFFS
--   * Every index costs disk space and slows every INSERT, UPDATE and DELETE,
--     because each index must be updated too. Add indexes for measured queries.
--   * On a small table the planner ignores the index on purpose: reading
--     everything is cheaper. A Seq Scan is not always a problem.
--   * CONCURRENTLY is slower and cannot run in a transaction. If it fails midway
--     it leaves an INVALID index that must be dropped by hand.
--   * One composite index serves queries that filter on a LEFT-PREFIX of its
--     columns (tenant_id alone, or tenant_id + created_at), not created_at alone.
--   * A covering index (INCLUDE columns) can avoid visiting the table at all, at
--     the cost of a bigger index.
