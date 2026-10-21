-- 07 | Row Level Security (RLS) for multi-tenant isolation.
--
-- Idea: the database itself refuses to return rows from another tenant, even if
-- the application forgets a WHERE clause. The app sets the current tenant per
-- transaction with SET LOCAL, which is also safe with PgBouncer transaction mode
-- (a plain SET would leak to the next client that reuses the connection).
--
-- Important: RLS does not apply to superusers or to the table owner (unless
-- FORCE is used). Run the app with a normal role such as app_user.

DROP TABLE IF EXISTS tickets_rls CASCADE;
CREATE TABLE tickets_rls (
  id        BIGSERIAL PRIMARY KEY,
  team_id   INT  NOT NULL,
  title     TEXT NOT NULL
);
INSERT INTO tickets_rls (team_id, title) VALUES (1, 'Printer broken'), (1, 'VPN down'), (2, 'Reset password');

ALTER TABLE tickets_rls ENABLE ROW LEVEL SECURITY;
ALTER TABLE tickets_rls FORCE ROW LEVEL SECURITY;

-- Rows are visible/writable only when team_id matches the transaction setting.
-- current_setting(..., true) returns NULL when never set, but an EMPTY STRING after a
-- SET LOCAL has ended on the same connection. NULLIF turns '' into NULL so the
-- cast does not fail; NULL never equals team_id, so no rows match: safe by default.
CREATE POLICY team_isolation ON tickets_rls
  USING      (team_id = NULLIF(current_setting('app.team_id', true), '')::int)
  WITH CHECK (team_id = NULLIF(current_setting('app.team_id', true), '')::int);

GRANT SELECT, INSERT, UPDATE, DELETE ON tickets_rls TO app_user;
GRANT USAGE, SELECT ON SEQUENCE tickets_rls_id_seq TO app_user;

SET ROLE app_user;

\echo '--- No tenant set: zero rows ---'
SELECT count(*) FROM tickets_rls;

BEGIN;
SET LOCAL app.team_id = '1';
\echo '--- Team 1 sees only its 2 tickets ---'
SELECT id, title FROM tickets_rls ORDER BY id;
COMMIT;

\echo '--- After COMMIT the setting is gone again: zero rows ---'
SELECT count(*) FROM tickets_rls;

RESET ROLE;
