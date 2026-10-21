-- init/01 | Least-privilege database roles.
--
-- PROBLEM THIS SOLVES
--   If the app connects as the database owner or a superuser, a single SQL
--   injection or bug can drop tables, read everything or ignore Row Level
--   Security. Each component should have only the permissions it needs, so a
--   mistake or a leaked password has a small blast radius.
--
-- RESULT
--   app_user      -> the application at runtime: read/write data, no schema changes
--   report_reader -> analytics and AI "data questions": read-only
--   (the superuser / migration role is used only to run migrations)
--
-- This file runs once, when the container is first created (it is mounted into
-- /docker-entrypoint-initdb.d). It does not run again on an existing volume.
--
-- The passwords below are for local development only. In a real environment
-- they would live in a secret manager (for example Azure Key Vault), one per role.

-- Step 1: the login roles. NOBYPASSRLS makes sure Row Level Security (script 07)
-- applies to them. They are not superusers and cannot create databases or roles.
CREATE ROLE app_user LOGIN PASSWORD 'app_dev_password' NOBYPASSRLS;
CREATE ROLE report_reader LOGIN PASSWORD 'report_dev_password' NOBYPASSRLS;

-- Step 2: close a classic hole. By default every user may create objects in the
-- public schema. Revoke that so only the owner can.
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

-- Step 3: let the roles look up objects in the schema. USAGE on the schema is
-- not enough on its own; they also need privileges on each table (step 4).
GRANT USAGE ON SCHEMA public TO app_user, report_reader;

-- Step 4: default privileges. Tables created LATER by the role that runs this
-- script (the migration role) are automatically readable by report_reader and
-- writable by app_user, so every new migration does not need its own GRANT.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON TABLES TO report_reader;

-- TRADE-OFFS
--   * ALTER DEFAULT PRIVILEGES only covers objects created by the role that ran
--     it. If migrations run as another role, the grants are not applied. Check
--     with \dp after the first migration.
--   * More roles mean more secrets to store, rotate and grant per application
--     (one Key Vault secret per role is the clean way).
--   * app_user can still delete rows. Least privilege here is about schema
--     changes and other users' roles, not about every row. Row Level Security
--     (script 07) narrows the rows.
--   * The init folder only runs on a fresh data volume. On an existing database
--     run the script by hand, or use a migration.
--   * Pointing report_reader (or an AI agent) at the live primary adds load and
--     can read sensitive columns. Prefer a read replica and column-level grants
--     or views for PII.
