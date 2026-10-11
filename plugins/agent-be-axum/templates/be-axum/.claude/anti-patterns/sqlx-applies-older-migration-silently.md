# sqlx applies a migration older than the newest applied one, out of order

**Applies to:** `sqlx migrate run` and `sqlx::migrate!`, sqlx 0.9
**Status:** A standing trap; `scripts/check/migrations.sh --base` refuses it in CI

## Symptom

Two branches each add a migration. The one with the earlier timestamp merges second, and
production applies it after the later one: `Applied 20261009000000/migrate late`, no error. A
column it assumed is not there yet, or it undoes what the newer one did.

## Root Cause

The migrator applies every file whose version is not in `_sqlx_migrations`, in version order,
with no check against the highest version already applied (sqlx 0.9.0 `migrator.rs`; reproduced
against PostgreSQL 17.11).

## Fix

A new migration's version is above the highest version on the base branch. When a rebase puts
yours below, rename it with a new timestamp before it merges (`sqlx migrate add` names files by
the current time). `migrations.sh --base <ref>` fails the pull request otherwise.

## When to revisit

If sqlx gains an ordering check, keep the CI check anyway: it costs nothing.
