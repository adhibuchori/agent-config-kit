# pgx `describe_exec` (or a cache with no pooler support) behind PgBouncer

**Applies to:** `internal/postgres`, whenever the service may run behind PgBouncer in transaction
mode.
**Status:** a standing trap (reproduced with pgx v5.11.0, PgBouncer 1.26.0, PostgreSQL 18.6).

## Symptom

Behind the pooler, with `default_query_exec_mode=describe_exec`, queries return **other clients'
results with no error**: 387 of 400 answers were wrong in the reproduction. With the default
`cache_statement` mode and a PgBouncer whose `max_prepared_statements` is 0, queries fail with
`prepared statement "stmtcache_..." already exists` (`42P05`) or `does not exist` (`26000`).

## Root cause

`describe_exec` prepares an unnamed statement in one round trip and executes it in the next; a
transaction pooler can hand the server connection to another client in between, whose unnamed
statement then runs with this client's parameters. pgx's own docs: "Do not use
QueryExecModeDescribeExec with transaction pooling." The statement cache needs the pooler to track
prepared statements per client, which PgBouncer does only with `max_prepared_statements` above 0
(added in 1.21, on by default since 1.24).

## Fix

- Keep pgx's default mode; `postgres.Config` refuses `describe_exec`.
- Run PgBouncer 1.21 or newer with `max_prepared_statements` above 0. If the pooler cannot, set
  `default_query_exec_mode=exec` in the connection string (no cache, one extra round trip).
- Prove it: the quality gate's `pgbouncer-tests` runs `internal/postgres/pooler_test.go` through
  the service's own pool constructor behind PgBouncer: 8 workers, 50 statements each, each with its
  own SQL text, every answer checked. Set `pgbouncer-max-prepared-statements: 0` to test against a
  production pooler that has the setting off.

## When to revisit

When pgx or PgBouncer changes how unnamed or named statements are handled.
