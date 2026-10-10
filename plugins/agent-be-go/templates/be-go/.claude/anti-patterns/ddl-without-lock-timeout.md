# DDL without `lock_timeout` stalls every query on the table

**Applies to:** every migration that alters, indexes or constrains an existing table.
**Status:** a standing trap (reproduced on PostgreSQL 18.6).

## Symptom

A migration that should take milliseconds (`ADD COLUMN`, `SET DEFAULT`, `ADD CONSTRAINT ... NOT
VALID`) runs during a deploy, and the API stops answering for as long as the slowest query or open
transaction on that table: plain `SELECT`s pile up behind it, the pool fills, health checks fail.

## Root cause

The DDL needs an `ACCESS EXCLUSIVE` lock (or another strong one) and waits in the lock queue behind
a long-running reader. Every later query on the table queues behind the waiting DDL, even ones the
DDL would not conflict with alone. Reproduced: with a 5-second reader in front, a plain `SELECT`
behind the waiting `ALTER TABLE` waited the full 5 seconds; with `lock_timeout = '1s'` the DDL gave
up after a second and the `SELECT` ran at once.

## Fix

- Every schema-changing migration sets a short `lock_timeout` first (`SET LOCAL lock_timeout =
  '3s'` in a transactional file; the migrator role's own `lock_timeout` in `db/roles.sql` backs it
  up). squawk's `require-lock-timeout` rule checks the file.
- The deploy retries a migration that failed on the lock timeout, a few times with a pause. The
  retry belongs to the deploy script, not to SQL.
- Keep transactions short everywhere, so nothing holds a table for long in the first place.

## When to revisit

Never: lock queueing is how PostgreSQL works.
