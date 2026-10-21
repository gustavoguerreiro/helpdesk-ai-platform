-- 03 | Declarative partitioning by time.
--
-- PROBLEM THIS SOLVES
--   Event and activity tables only grow. Two things hurt as they get big:
--     1. Retention: deleting old rows with DELETE is slow, writes a lot of WAL
--        and leaves dead space (bloat) that VACUUM must clean later.
--     2. Queries filtered by time still have to walk big indexes and big heaps.
--   Partitioning splits one logical table into many physical ones, one per month.
--
-- WHAT YOU SHOULD SEE
--   * In the first EXPLAIN: "Subplans Removed: 12". Only the current partitions
--     (plus the default one) are read. This is partition pruning.
--   * At the end: the name of the oldest partition, which could be dropped instantly.

-- Step 1: start clean.
DROP TABLE IF EXISTS events_p CASCADE;

-- Step 2: the parent table. It holds no rows itself. PARTITION BY RANGE sends
-- each row to a child table according to created_at.
CREATE TABLE events_p (
  id         BIGSERIAL,
  tenant_id  INT         NOT NULL,
  kind       TEXT        NOT NULL,
  created_at TIMESTAMPTZ NOT NULL,
  payload    JSONB       NOT NULL DEFAULT '{}',
  PRIMARY KEY (id, created_at)          -- must include the partition key
) PARTITION BY RANGE (created_at);

-- Step 3: one partition per month, from 12 months ago to the next month (14 in
-- total), created with a loop. format() builds the SQL text with safely quoted
-- values (%L) and EXECUTE runs it.
DO $$
DECLARE
  month_start date := date_trunc('month', now() - interval '12 months')::date;
  i int;
BEGIN
  FOR i IN 0..13 LOOP
    EXECUTE format(
      'CREATE TABLE events_p_%s PARTITION OF events_p FOR VALUES FROM (%L) TO (%L)',
      to_char(month_start + (i || ' months')::interval, 'YYYY_MM'),
      month_start + (i || ' months')::interval,
      month_start + ((i + 1) || ' months')::interval
    );
  END LOOP;
END $$;

-- Step 4: a default partition catches rows that fall outside every defined range,
-- so an insert never fails just because a partition was not created yet.
CREATE TABLE events_p_default PARTITION OF events_p DEFAULT;

-- Step 5: an index on the parent. Postgres creates it on every partition
-- automatically, including partitions added later.
CREATE INDEX events_p_tenant_created_idx ON events_p (tenant_id, created_at);

-- Step 6: copy the data from script 01 and refresh statistics.
INSERT INTO events_p (tenant_id, kind, created_at, payload)
SELECT tenant_id, kind, created_at, payload FROM events;
ANALYZE events_p;

-- Step 7: show partition pruning. A filter on the partition key lets the planner
-- skip partitions that cannot match. Because now() is only known at run time, the
-- planner removes them while executing ("Subplans Removed").
\echo '--- Partition pruning: old partitions are removed from the plan ---'
-- Note: the DEFAULT partition is always scanned, because it can hold any date.
-- Keep it empty by creating partitions ahead of time.
EXPLAIN (COSTS OFF)
SELECT count(*) FROM events_p
WHERE created_at >= date_trunc('month', now());

-- Step 8: retention. List the oldest partition. Removing it is a metadata
-- operation, not a row-by-row delete.
\echo '--- Retention: dropping the oldest partition is instant (no big DELETE) ---'
SELECT relname FROM pg_class
WHERE relname LIKE 'events_p_20%' AND relkind = 'r'
ORDER BY relname LIMIT 1;
-- Example (not executed here): DROP TABLE events_p_2025_10;
-- To keep the data instead: ALTER TABLE events_p DETACH PARTITION events_p_2025_10;

-- TRADE-OFFS
--   * The primary key must include the partition column, so id alone is not
--     unique for the database. A foreign key pointing at events_p(id) is not
--     possible; you reference (id, created_at) or enforce it in the app.
--   * New partitions must be created ahead of time by a scheduled job. If the
--     job fails, rows land in the DEFAULT partition, which is then always
--     scanned and makes creating the missing partition slower (rows must move).
--   * A query WITHOUT a filter on created_at reads every partition and can be
--     slower than on one big table.
--   * Too many partitions (thousands) slow planning. Monthly is a common start.
--   * It pays off for big tables with time-based retention or time-filtered
--     queries. On a small table it is extra complexity for no gain.
--   * Converting an existing table to partitioned needs a copy or a swap; plan it
--     like the expand and contract pattern in script 06.
