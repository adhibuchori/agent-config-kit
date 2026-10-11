---
paths:
  - 'db/**'
  - 'migrations/**'
  - '**/*.sql'
  - 'internal/postgres/**'
  - 'src/**/repo.rs'
  - 'src/platform/db.rs'
  - '.squawk.toml'
---

# PostgreSQL

How this service uses PostgreSQL: the roles, the pool, the migrations and the queries. The rule
statements are the index in `AGENTS.md`; the traps behind them are in `.claude/anti-patterns/`.

## Version

Target PostgreSQL 18, accept 17 as the floor. A migration that needs 18 (a `uuidv7()` default,
`NOT NULL ... NOT VALID`) says so in a comment on its first line, because production may run 17.

## Roles and timeouts

`db/roles.sql` creates three roles, runs in CI on the test database, and is the record of what
production holds:

| Role | Used by | Holds |
| --- | --- | --- |
| `app_owner` | the migrator | owns every object; `lock_timeout` so a migration fails fast instead of queueing reads |
| `app_rw` | the running service | DML on the app schema only; `statement_timeout`, `lock_timeout`, `idle_in_transaction_session_timeout`, `transaction_timeout` |
| `agent_ro` | read-only database MCP servers | `SELECT` only; its read-only default is a default, the grants are the boundary |

- Timeouts live on the role (`ALTER ROLE app_rw SET ...`). A transaction pooler refuses them as
  startup parameters, and a session `SET` leaks to the next client of that connection. A changed
  value reaches only new connections, so roll the service after changing one.
- `ALTER DEFAULT PRIVILEGES FOR ROLE app_owner`: default privileges follow the role that creates
  the objects, and the migrator creates them.
- The service connects as `app_rw`, never as the owner; the tests do too, so a missing grant or
  timeout fails a test.

## Pool

- Set the pool size explicitly, at 3 or more: the drivers' defaults follow the CPU count or a fixed
  number, and one or two connections serialize every request. Budget: the sum over every instance
  of its pool size, plus the migrator, the agents and monitoring, stays below `max_connections`
  minus the reserved slots. `CONNECTION LIMIT` on the role is the fence.
- Behind PgBouncer in transaction mode: 1.21 or newer with `max_prepared_statements` above 0 (the
  default since 1.24), no session `SET`, no session advisory lock, no `LISTEN`, no `WITH HOLD`
  cursor. The driver's "describe, then execute" or unnamed-statement modes can return another
  client's result there. The quality gate can run the service's own pool through PgBouncer
  (`pgbouncer-tests`).
- The migrator connects directly, never through a transaction pooler: it holds a session-level
  advisory lock for the whole run.

## Migrations

- A migration that reached a protected branch never changes: a database may have run it. A change
  is a new file with a higher version; the migration guard refuses edits to merged files, and the
  gate refuses a changed, deleted, renamed or out-of-order file against the base branch.
- Deploy without downtime: expand (add, nullable or with a constant default), backfill in batches,
  switch the code, contract (drop) in a later release. A rename is add, backfill, drop.
- `CREATE INDEX CONCURRENTLY` runs alone, in a file the tool runs outside a transaction. A failed
  one leaves an INVALID index that `IF NOT EXISTS` then hides: drop it (`DROP INDEX CONCURRENTLY`)
  and build it again. The gate fails on any index with `pg_index.indisvalid = false`.
- Each schema-changing file sets `lock_timeout` (a few seconds) so it never queues every query on
  its table; the deploy retries a migration that timed out.
- `NOT NULL` on a filled table: add `CHECK (col IS NOT NULL) NOT VALID`, then `VALIDATE`, then
  `SET NOT NULL`, then drop the check (18: `NOT NULL ... NOT VALID` directly). A foreign key on a
  filled table: `NOT VALID`, then `VALIDATE CONSTRAINT` in the next file.
- `ALTER TYPE ... ADD VALUE` goes in a file of its own: the new value cannot be used in the
  transaction that added it. Prefer a lookup table or a `CHECK` for values the product changes.
- squawk (`.squawk.toml`) lints every new migration in the gate.

## Indexes

Every foreign key has an index whose leading columns are the key's columns, in the migration that
adds the key: PostgreSQL does not create one, and a delete on the parent then scans the child. The
gate runs this query on the migrated test database and fails on any row:

```sql
select c.conrelid::regclass as table_name, c.conname as constraint_name
from pg_constraint c
join pg_class rel on rel.oid = c.conrelid
join pg_namespace ns on ns.oid = rel.relnamespace
where c.contype = 'f'
  and ns.nspname not in ('pg_catalog', 'information_schema') and ns.nspname !~ '^pg_toast'
  and not exists (select 1 from pg_index i
                  where i.indrelid = c.conrelid and i.indisvalid and i.indpred is null
                    and (i.indkey::int2[])[0 : cardinality(c.conkey) - 1] @> c.conkey);
```

A filter or join column on a table that grows past 100,000 rows gets an index too, with the
`EXPLAIN` in the pull request.

## Queries

- A query that returns a list has a `LIMIT` and pages by key (`WHERE (created_at, id) < ($1, $2)
  ORDER BY created_at DESC, id DESC LIMIT $3`), never by `OFFSET` on a large table.
- Name the columns. `SELECT *` changes shape when a column is added, and a cached plan then fails
  with "cached plan must not change result type".
- One query per set, not per row: batch with `= ANY($1)`, a multi-row `INSERT ... ON CONFLICT`, or
  `COPY`. A query inside a loop is the N+1 the reviewer looks for.
- A transaction is short, lives in the store, and holds no network call: the idle-in-transaction
  timeout ends a session that waits on one.

## Types

`timestamptz` (never `timestamp`), `text` with a `CHECK` on length, `numeric` for money,
`jsonb`, and identity columns (`generated always as identity`; `serial` needs grants on its
sequence). Primary keys: `uuidv7()` on 18 (ordered, a denser index), or a v7 generated by the
service; a value that must not be guessed is a v4 or a random token.
