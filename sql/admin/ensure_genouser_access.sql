-- Ensure application DB role 'genouser' exists, has the expected password, and proper privileges.
-- Paste into Adminer (connected to the 'genomics' database) and execute.

-- 1) Create role if missing, and set password
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='genouser') THEN
    CREATE ROLE genouser LOGIN PASSWORD 'a257272733aa65612215928f75083ae9621e9e3876b15f5e';
  END IF;
END$$;

ALTER ROLE genouser WITH LOGIN PASSWORD 'a257272733aa65612215928f75083ae9621e9e3876b15f5e';

-- 2) Database connect privilege (adjust DB name if different)
GRANT CONNECT ON DATABASE genomics TO genouser;

-- 3) Schema usage
GRANT USAGE ON SCHEMA public TO genouser;
GRANT USAGE ON SCHEMA anno   TO genouser;

-- 4) Table privileges for current objects
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO genouser;
GRANT SELECT                         ON ALL TABLES IN SCHEMA anno   TO genouser;

-- 5) Sequence privileges for current objects
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO genouser;

-- 6) Default privileges for future objects (run as a role that owns the objects, typically the schema owner)
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO genouser;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO genouser;
ALTER DEFAULT PRIVILEGES IN SCHEMA anno   GRANT SELECT ON TABLES TO genouser;
