# db-migration

Skill · agent-be-go · `agent-be-go:db-migration` · writes a new migration and its tests · no network

## What it does

The `db-migration` skill writes a PostgreSQL schema change as a new goose migration that deploys
without downtime: it plans expand, backfill and contract as separate migrations, builds a new index
concurrently in a file goose runs outside a transaction, adds each foreign key's index in the same
change, applies the migrations to the test database, regenerates the query code and proves the
change with a test at the store seam.

## When to reach for it

Claude loads it when a task adds, alters or drops a table, column, index, constraint or enum value:

```text
Add an archived_at column to invoices and an index for listing the archived ones.
```

**Not for:** a query change on an unchanged schema, and never for editing a migration that is
already merged; [migration-guard](migration-guard.md) refuses that.

## Prerequisites

- A PostgreSQL 18 test database with `db/roles.sql` applied (`.claude/rules/backend/testing.md`).
- `go.mod`'s `tool` lines for goose and sqlc.

## Common questions

**Why three migrations for one change?**
Old and new code run side by side during a deploy. Expand keeps the old code working, the backfill
moves data in batches, and the contract drops the old shape only once nothing deployed reads it.

**Why a file of its own for the index?**
`CREATE INDEX CONCURRENTLY` cannot run in a transaction, and goose runs each file in one unless it
says `-- +goose NO TRANSACTION`.

## It's working if

- `bash scripts/check/migrations.sh` passes on the new files, and the gate's database built from
  scratch shows no foreign key without an index and no invalid index.
- `git diff` shows only new files under `db/migrations`.

## Where it fits

One of the two procedure skills of [agent-be-go](../../plugins/agent-be-go/README.md), next to
[api-endpoint](api-endpoint.md).
