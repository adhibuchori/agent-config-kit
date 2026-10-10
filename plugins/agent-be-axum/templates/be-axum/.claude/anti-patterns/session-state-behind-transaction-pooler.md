# Session state behind a transaction pooler

**Applies to:** any service that reaches PostgreSQL through PgBouncer (or another pooler) in
transaction mode.
**Status:** a standing trap (reproduced with PgBouncer 1.26.0 and PostgreSQL 18.6).

## Symptom

One client's setting shows up in another client's queries. A request that ran
`SET statement_timeout = '1234ms'` leaves that timeout on the server connection, and the next
request from a different service instance, given the same server connection, reads `1234ms`. An
advisory lock taken with `pg_advisory_lock` stays held after the request that took it is gone. A
`LISTEN` never hears its `NOTIFY`.

## Root cause

In transaction mode the pooler hands a server connection to a client for one transaction, then to
the next client. Anything that lives in the session outlives the transaction: `SET` (without
`LOCAL`), session advisory locks, `LISTEN`, prepared statements made with SQL `PREPARE`, temporary
tables without `ON COMMIT DROP`, `WITH HOLD` cursors. PgBouncer's feature table marks each of these
"Never" for transaction pooling.

## Fix

- Settings that every session needs live on the role: `ALTER ROLE app_rw SET statement_timeout = '10s'`
  (`db/roles.sql`). They apply at login, which the pooler's server connections do as that role.
- A setting one transaction needs: `SET LOCAL`, or `select set_config('name', $1, true)` inside the
  transaction; both end with it.
- `pg_advisory_xact_lock` instead of `pg_advisory_lock`: it is released at commit.
- `LISTEN` and anything else that needs a session: a direct connection, not the pooler.

## When to revisit

If the pooler moves to session mode for this service, or PgBouncer starts tracking these per
client.
