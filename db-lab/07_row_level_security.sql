-- 07 | Row Level Security (RLS) for multi-tenant isolation.
--
-- PROBLEM THIS SOLVES
--   In a multi-tenant app, one forgotten "WHERE team_id = ..." leaks another
--   team's data. With RLS the database itself refuses to return (or write) rows
--   from another team, even if the application forgets the filter. The app tells
--   the database who it is acting for, once per transaction.
--
-- HOW THE APP USES IT
--   BEGIN;
--   SET LOCAL app.team_id = '<team of the current user>';
--   ... normal queries; the policy filters every row ...
--   COMMIT;
--   SET LOCAL lasts only until the end of the transaction. That is what makes it
--   safe with PgBouncer in transaction mode: a plain SET belongs to the
--   connection and would leak to the next client that reuses it.
--
-- WHAT YOU SHOULD SEE
--   No team set -> 0 rows. Team 1 set -> its 2 tickets. After COMMIT -> 0 rows.
--
-- Important: RLS does not apply to superusers or roles with BYPASSRLS, nor to the
-- table owner unless FORCE is used. Run the app with a normal role such as
-- app_user (see init/01-roles.sql).

-- Step 1: a small table with two teams.
DROP TABLE IF EXISTS tickets_rls CASCADE;
CREATE TABLE tickets_rls (
  id        BIGSERIAL PRIMARY KEY,
  team_id   INT  NOT NULL,
  title     TEXT NOT NULL
);
INSERT INTO tickets_rls (team_id, title) VALUES (1, 'Printer broken'), (1, 'VPN down'), (2, 'Reset password');

-- Step 2: turn RLS on. FORCE also applies it to the table owner; without FORCE
-- the owner would silently see everything.
ALTER TABLE tickets_rls ENABLE ROW LEVEL SECURITY;
ALTER TABLE tickets_rls FORCE ROW LEVEL SECURITY;

-- Step 3: the policy. Rows are visible/writable only when team_id matches the
-- transaction setting.
--   USING       filters the rows you can read, update or delete
--   WITH CHECK  validates the rows you insert or update, so nobody can write a
--               row into another team
-- current_setting(..., true) returns NULL when never set, but an EMPTY STRING after a
-- SET LOCAL has ended on the same connection. NULLIF turns '' into NULL so the
-- cast does not fail; NULL never equals team_id, so no rows match: safe by default.
CREATE POLICY team_isolation ON tickets_rls
  USING      (team_id = NULLIF(current_setting('app.team_id', true), '')::int)
  WITH CHECK (team_id = NULLIF(current_setting('app.team_id', true), '')::int);

-- Step 4: normal table permissions. RLS filters rows; GRANT still decides who may
-- touch the table at all. The sequence grant lets the role insert (BIGSERIAL id).
GRANT SELECT, INSERT, UPDATE, DELETE ON tickets_rls TO app_user;
GRANT USAGE, SELECT ON SEQUENCE tickets_rls_id_seq TO app_user;

-- Step 5: act as the application role. The script's own login is a superuser here,
-- which would bypass RLS and make the demo meaningless.
SET ROLE app_user;

-- Step 6: no team set. Safe by default: nothing is visible.
\echo '--- No tenant set: zero rows ---'
SELECT count(*) FROM tickets_rls;

-- Step 7: set the team for one transaction.
BEGIN;
SET LOCAL app.team_id = '1';
\echo '--- Team 1 sees only its 2 tickets ---'
SELECT id, title FROM tickets_rls ORDER BY id;
COMMIT;

-- Step 8: the setting is gone with the transaction.
\echo '--- After COMMIT the setting is gone again: zero rows ---'
SELECT count(*) FROM tickets_rls;

RESET ROLE;

-- TRADE-OFFS
--   * RLS is a safety net, not a replacement for application authorization. It
--     does not know about roles inside a team, pages or widgets.
--   * It only protects connections that use a role without BYPASSRLS. A
--     superuser or migration role ignores it, so the app must never use those.
--   * Every query pays for the policy as an extra filter. Index team_id (usually
--     as the first column of the indexes that matter).
--   * The app must open a transaction per request to run SET LOCAL. Prisma has no
--     built-in RLS support; the usual pattern is an interactive transaction (or a
--     client extension) that sets the variable before the queries.
--   * A forgotten SET LOCAL returns zero rows, not an error. That is safe but can
--     look like a bug ("my data disappeared"), so test for it.
--   * Policies add complexity: separate rules for read and write, cross-team
--     roles (a manager seeing several teams) and admin access all need their own
--     policies. Materialized views and some views do not enforce RLS.
--   * This script ran over a direct connection. SET LOCAL through PgBouncer in
--     transaction mode follows from how SET LOCAL works but was not run here.
