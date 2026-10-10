-- The database roles of every environment (PostgreSQL 18 target, 17 floor), run as a superuser:
--
--   psql "<superuser connection string>" -v ON_ERROR_STOP=1 [-v db=<database>] -f db/roles.sql
--
-- The roles are per cluster; the database and its schema are created when missing. Without -v db,
-- the database is app_test, the one the quality gate and .env.ci.example use, so the gate and a
-- local throwaway container run the file as it is; production names its own. Running it again
-- changes nothing. It sets no password: production sets each one out of band (\password), while
-- CI and a local throwaway container use trust authentication.
--
--   app_owner  runs the migrations and owns every object; never the service's login.
--   app_rw     the running service: DML only. Its timeouts live here, on the role, so they hold
--              behind a transaction pooler, which refuses them as startup parameters.
--   agent_ro   the read-only database MCP servers: its privileges are the boundary; its read-only
--              default is only a default that a session can switch off.
\if :{?db}
\else
\set db app_test
\endif

SELECT format('CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE', r)
FROM unnest(ARRAY['app_owner', 'app_rw', 'agent_ro']) AS r
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r)
\gexec

-- A connection budget per role: the sum over every service and tool stays under max_connections.
ALTER ROLE app_rw CONNECTION LIMIT 40;
ALTER ROLE agent_ro CONNECTION LIMIT 3;

-- statement_timeout cancels one statement; lock_timeout stays below it; the idle-in-transaction
-- and transaction timeouts (17+) end a session that holds a transaction open too long.
ALTER ROLE app_rw SET statement_timeout = '10s';
ALTER ROLE app_rw SET lock_timeout = '3s';
ALTER ROLE app_rw SET idle_in_transaction_session_timeout = '15s';
ALTER ROLE app_rw SET transaction_timeout = '30s';
ALTER ROLE app_rw SET search_path = app, pg_catalog;

-- The migrator waits briefly for a lock and then fails (the deploy retries), so a migration never
-- queues every other query on its table; it has no statement timeout, because building an index
-- concurrently takes as long as it takes.
ALTER ROLE app_owner SET lock_timeout = '3s';
ALTER ROLE app_owner SET idle_in_transaction_session_timeout = '60s';
ALTER ROLE app_owner SET search_path = app, pg_catalog;

ALTER ROLE agent_ro SET default_transaction_read_only = on;
ALTER ROLE agent_ro SET statement_timeout = '15s';
ALTER ROLE agent_ro SET lock_timeout = '2s';
ALTER ROLE agent_ro SET idle_session_timeout = '10min';
ALTER ROLE agent_ro SET search_path = app, pg_catalog;

SELECT format('CREATE DATABASE %I OWNER app_owner', :'db')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db')
\gexec

-- PUBLIC holds CONNECT and TEMP on a new database; only the named roles connect.
REVOKE ALL ON DATABASE :"db" FROM PUBLIC;
GRANT CONNECT ON DATABASE :"db" TO app_rw, agent_ro;

\connect :"db"

-- The default since PostgreSQL 15, stated for a database upgraded from an older one.
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
CREATE SCHEMA IF NOT EXISTS app AUTHORIZATION app_owner;
GRANT USAGE ON SCHEMA app TO app_rw, agent_ro;

-- FOR ROLE app_owner: default privileges apply to the objects that role creates. Without it they
-- would apply to objects the superuser running this file creates, and the migrator's tables would
-- grant nothing.
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA app
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_rw;
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA app
  GRANT USAGE, SELECT ON SEQUENCES TO app_rw;
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA app
  GRANT SELECT ON TABLES TO agent_ro;

-- Objects that already exist when this runs again.
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO app_rw;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA app TO app_rw;
GRANT SELECT ON ALL TABLES IN SCHEMA app TO agent_ro;
