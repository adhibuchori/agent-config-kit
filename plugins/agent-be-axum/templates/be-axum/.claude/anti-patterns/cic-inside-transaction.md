# `CREATE INDEX CONCURRENTLY` inside a transaction

**Applies to:** every migration runner that wraps a file in a transaction, which is the default
for the ones this kit uses.
**Status:** a standing trap (reproduced on 18.6, 17.11 and 16.15).

## Symptom

A migration that adds an index without blocking writes fails on every database with
`ERROR: CREATE INDEX CONCURRENTLY cannot run inside a transaction block`. Removing `CONCURRENTLY`
makes it pass and locks the table against writes for the whole build in production.

## Root cause

The PostgreSQL docs: "a regular CREATE INDEX command can be performed within a transaction block,
but CREATE INDEX CONCURRENTLY cannot." A migration runner sends a whole file inside one
transaction unless the file opts out, and a file of several statements sent as one query string is
an implicit transaction too. `DROP INDEX CONCURRENTLY` and `REINDEX ... CONCURRENTLY` have the same
limit.

## Fix

Put the concurrent build in a file of its own, as its only statement, marked so the runner sends
it outside a transaction: the runner's no-transaction marker is the file's first line (the
migration skill's steps name it for this stack). The gate fails a concurrent build in a file
without the marker. Keep the rest of the change (the column, the constraint) in the ordinary,
transactional file before it.

## When to revisit

If PostgreSQL allows concurrent index builds in a transaction block.
