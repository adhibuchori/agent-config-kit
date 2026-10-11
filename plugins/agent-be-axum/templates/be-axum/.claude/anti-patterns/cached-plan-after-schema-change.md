# `cached plan must not change result type` after a migration

**Applies to:** every driver that prepares and caches statements (the default for the drivers this
kit uses), and PgBouncer's shared prepared statements.
**Status:** a standing trap (reproduced on PostgreSQL 18.6).

## Symptom

Right after a deploy that adds a column, requests fail with
`ERROR: cached plan must not change result type` (SQLSTATE `0A000`) until the service restarts or
the pooler reconnects. Only some queries fail: the ones written as `SELECT *` or `RETURNING *`.

## Root cause

A prepared statement fixes its result columns when it is prepared. `ALTER TABLE ... ADD COLUMN`
changes what `*` expands to, so the next execution of a cached `SELECT *` would return a different
shape, and PostgreSQL refuses it. The driver's cache and PgBouncer's `max_prepared_statements`
keep those statements across requests; PgBouncer's docs suggest `RECONNECT` on its admin console.
A statement that names its columns keeps its shape.

## Fix

- Name the columns in every query and every `RETURNING`.
- Additive migrations only, with the code that reads a new column deployed after the column
  exists (expand, then switch).
- After a migration that changes a column's type, roll the service so every connection prepares
  afresh.

## When to revisit

Never, while statements are cached across a schema change.
