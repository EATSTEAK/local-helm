\set ON_ERROR_STOP on
\getenv app_database APP_DATABASE
\getenv app_owner APP_OWNER
\getenv app_password APP_PASSWORD
\getenv app_connection_limit APP_CONNECTION_LIMIT

-- Serialize bootstraps for this instance, including multiple app databases.
SELECT pg_advisory_lock(71402);

-- Refuse to adopt an existing privileged role or somebody else's database.
SELECT EXISTS (
  SELECT 1 FROM pg_roles
  WHERE rolname = :'app_owner'
    AND (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls
      OR EXISTS (SELECT 1 FROM pg_auth_members WHERE member = pg_roles.oid))
) AS unsafe_role \gset
\if :unsafe_role
  DO $$ BEGIN RAISE EXCEPTION 'Refusing to adopt a privileged application role'; END $$;
\endif
SELECT EXISTS (
  SELECT 1 FROM pg_database
  WHERE datname = :'app_database'
    AND pg_get_userbyid(datdba) <> :'app_owner'
) AS wrong_owner \gset
\if :wrong_owner
  DO $$ BEGIN RAISE EXCEPTION 'Refusing to adopt a database owned by another role'; END $$;
\endif

SELECT format(
  'CREATE ROLE %I LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS',
  :'app_owner'
) WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'app_owner') \gexec

-- Reconcile the explicitly supplied Secret; never generate/rotate it here.
SELECT format('ALTER ROLE %I LOGIN CONNECTION LIMIT %s PASSWORD %L',
  :'app_owner', :'app_connection_limit'::integer, :'app_password') \gexec

SELECT format('CREATE DATABASE %I OWNER %I', :'app_database', :'app_owner')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'app_database') \gexec

REVOKE CONNECT ON DATABASE postgres FROM PUBLIC;
REVOKE CONNECT ON DATABASE template1 FROM PUBLIC;
REVOKE ALL ON DATABASE :"app_database" FROM PUBLIC;
GRANT CONNECT, TEMPORARY ON DATABASE :"app_database" TO :"app_owner";
SELECT pg_advisory_unlock(71402);

\connect :app_database
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO :"app_owner";
