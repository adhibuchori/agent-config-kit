# pgxpool's size follows the machine's CPU count

**Applies to:** `internal/postgres` and the `DB_MAX_CONNS` setting.
**Status:** a standing trap (read in pgx v5.11.0 `pgxpool/pool.go`).

## Symptom

The service runs fine on a laptop and on a 2-vCPU instance, then, moved to a 64-core node, opens up
to 64 connections per replica: ten replicas exhaust `max_connections`, and every other service and
the migrator start failing with `too many clients already`. Or the reverse: a small container gets
4 connections and requests queue.

## Root cause

When the pool size is not set, pgxpool uses "the greater of 4 or runtime.NumCPU()". The size then
depends on where the process lands, not on the database's budget. `database/sql`, which a library
such as goose may open on its own, defaults to no limit at all.

## Fix

- The size is always explicit: `DB_MAX_CONNS` (3 to 1000, default 10) through `internal/config`,
  and `postgres.Config` sets it with every lifetime and the connect timeout. Fewer than 3 is
  refused: with one or two connections every request queues behind the others.
- Budget it: the sum over every replica of its pool size, plus the migrator, the agents and
  monitoring, stays below `max_connections` minus the reserved slots. `CONNECTION LIMIT` on the
  role (`db/roles.sql`) is the fence when the sum is wrong.
- A tool that opens its own `*sql.DB` gets `SetMaxOpenConns` too.

## When to revisit

If pgx changes its default.
