# db-migration

Skill · agent-be-axum · `agent-be-axum:db-migration` · writes a new migration and refreshes the query cache · uses your local database

## What it does

The `db-migration` skill writes a PostgreSQL schema change as a new sqlx migration that deploys
without downtime: expand, backfill, contract, each phase its own file. A concurrent index stands
alone in a file that starts with `-- no-transaction`, a new foreign key gets its index in the same
file, and a constraint on existing rows is added `NOT VALID` and validated later. It then applies the
migrations to an empty database and regenerates the offline query cache.

## When to reach for it

Claude loads it when a task adds, alters or drops a table, column, index, constraint or enum value:

```text
Add a nullable shipped_at column to orders, and index it.
```

**Not for:** a query change that leaves the schema as it is, or editing a migration a protected
branch already has; [migration-guard](migration-guard.md) refuses that.

## Prerequisites

- sqlx-cli 0.9.0 and a local PostgreSQL at `DATABASE_URL` for `sqlx migrate run` and
  `cargo sqlx prepare`.
- `migrations/` in this repo (setup's `migrations=yes`).

## Common questions

**Why one phase per pull request?**
Old and new code run side by side during a deploy. A column the old code still reads can only go
once no deployed version reads it.

**CI says my version is not above the base's highest.**
A rebase put your migration below a newer one on the base branch; give it a new timestamp. sqlx
would otherwise apply it out of order without a word.

## It's working if

- `git diff` shows a new file under `migrations/` and a refreshed `.sqlx/`, and no change to a
  merged migration.
- `bash scripts/check/gates.sh` passes, including the database tier.

## Where it fits

One of the two skills of [agent-be-axum](../../plugins/agent-be-axum/README.md), next to
[api-endpoint](api-endpoint.md).
