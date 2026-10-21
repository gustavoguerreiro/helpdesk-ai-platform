-- 03 | Declarative partitioning by time.
--
-- Why partition a large event/activity table?
--   * Old data can be removed with DROP/DETACH of a partition (instant),
--     instead of a huge DELETE that bloats the table.
--   * Queries filtered by time only touch the relevant partitions
--     ("partition pruning").
--   * Maintenance (VACUUM, indexes) works per partition.
--
-- Trade-offs:
--   * The primary key must include the partition column.
--   * New partitions must be created ahead of time (a routine job).

DROP TABLE IF EXISTS events_p CASCADE;

CREATE TABLE events_p (
  id         BIGSERIAL,
  tenant_id  INT         NOT NULL,
  kind       TEXT        NOT NULL,
  created_at TIMESTAMPTZ NOT NULL,
  payload    JSONB       NOT NULL DEFAULT '{}',
  PRIMARY KEY (id, created_at)          -- must include the partition key
) PARTITION BY RANGE (created_at);

-- One partition per month for the last 13 months, created with a loop.
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

-- A default partition catches rows that fall outside every defined range,
-- so an insert never fails just because a partition was not created yet.
CREATE TABLE events_p_default PARTITION OF events_p DEFAULT;

-- Index on the parent: Postgres creates it on every partition automatically.
CREATE INDEX events_p_tenant_created_idx ON events_p (tenant_id, created_at);

INSERT INTO events_p (tenant_id, kind, created_at, payload)
SELECT tenant_id, kind, created_at, payload FROM events;
ANALYZE events_p;

\echo '--- Partition pruning: old partitions are removed from the plan ---'
-- Note: the DEFAULT partition is always scanned, because it can hold any date.
-- Keep it empty by creating partitions ahead of time.
EXPLAIN (COSTS OFF)
SELECT count(*) FROM events_p
WHERE created_at >= date_trunc('month', now());

\echo '--- Retention: dropping the oldest partition is instant (no big DELETE) ---'
SELECT relname FROM pg_class
WHERE relname LIKE 'events_p_20%' AND relkind = 'r'
ORDER BY relname LIMIT 1;
-- Example (not executed here): DROP TABLE events_p_2025_10;
