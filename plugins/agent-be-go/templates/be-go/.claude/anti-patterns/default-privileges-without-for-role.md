# `ALTER DEFAULT PRIVILEGES` without `FOR ROLE`

**Applies to:** the role bootstrap (`db/roles.sql`) and any grant script run by a superuser.
**Status:** a standing trap (reproduced on PostgreSQL 18.6).

## Symptom

The bootstrap ran without an error, the migrations ran, and the service's first query fails with
`ERROR: permission denied for table things`. Granting by hand fixes that table; the next migration's
table fails the same way.

## Root cause

Default privileges belong to the role that creates the objects. Run as the superuser,
`ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT ... TO app_rw` registers defaults for objects the
**superuser** creates. The migrator, `app_owner`, creates the tables, so they get nothing. The docs:
new object permissions "are not inherited from any roles in which the current role is a member".

## Fix

Name the creating role:

```sql
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA app
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_rw;
```

and grant on what already exists when the file runs again
(`GRANT ... ON ALL TABLES IN SCHEMA app TO app_rw`). The service's tests connect as `app_rw` after
the migrations ran as `app_owner`, so a missing grant fails a test, not production.

## When to revisit

If the migrator ever runs as a different role: name that role instead.
