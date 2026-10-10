# A read-only default is not a read-only role

**Applies to:** the role an agent's database MCP server (`db-dev`, `db-prod`) or any reporting tool
connects as.
**Status:** a standing trap (reproduced on PostgreSQL 18.6).

## Symptom

A role set up as "read-only" with `ALTER ROLE agent_ro SET default_transaction_read_only = on`
writes after all: a session runs `SET default_transaction_read_only = off` or `BEGIN READ WRITE`,
and the `INSERT` goes through whenever the role also holds write grants.

## Root cause

`default_transaction_read_only` is a default each session may change. Only privileges stop a write.
The postgres-mcp server's own README says PostgreSQL "does not provide a way to place a connection
or session into read-only mode".

## Fix

Give the role nothing it could write with, and keep the default only as a second net:

```sql
GRANT USAGE ON SCHEMA app TO agent_ro;
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA app GRANT SELECT ON TABLES TO agent_ro;
ALTER ROLE agent_ro SET default_transaction_read_only = on;
```

With only `SELECT`, the `INSERT` fails with `permission denied` even after the session switches
the default off. `pg_read_all_data` (14+) reads every schema in the database, auth and personal
data included; prefer per-schema grants when the database holds data the agent must not read.

## When to revisit

If PostgreSQL adds an enforced read-only session mode.
