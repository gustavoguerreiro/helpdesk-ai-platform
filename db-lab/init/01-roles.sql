-- Least-privilege database roles (runs once when the container is first created).
--
-- Principle: every component gets only the permissions it needs.
--   app_user      -> the application at runtime: read/write data, no schema changes
--   report_reader -> analytics and AI "data questions": read-only
--   (the superuser / migration role is used only to run migrations)
--
-- The passwords below are for local development only. In a real environment
-- they would live in a secret manager (for example Azure Key Vault), one per role.

CREATE ROLE app_user LOGIN PASSWORD 'app_dev_password' NOBYPASSRLS;
CREATE ROLE report_reader LOGIN PASSWORD 'report_dev_password' NOBYPASSRLS;

-- Nobody except the owner may create objects in the public schema.
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

GRANT USAGE ON SCHEMA public TO app_user, report_reader;

-- Default privileges: tables created later by the migration role are
-- automatically readable by report_reader and writable by app_user.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON TABLES TO report_reader;
