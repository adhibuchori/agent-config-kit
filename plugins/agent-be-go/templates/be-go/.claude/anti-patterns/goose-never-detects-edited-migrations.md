# goose never notices an edited migration

**Applies to:** `db/migrations`, and every pull request that touches it.
**Status:** a standing trap (read in goose v3.28.0; golang-migrate and tern behave the same).

## Symptom

A migration that already ran in production is "fixed" in place: a column type corrected, an index
added to it. CI is green, the deploy is green, and production never gets the change, because goose
sees the version as applied. A new environment built from scratch does get it, and the two
databases now disagree.

## Root cause

goose records only versions (`goose_db_version`: id, version_id, is_applied, tstamp). It keeps no
checksum of a file's content, so an edit to an applied file is invisible to it. (Atlas keeps
checksums, but its linting needs the proprietary build and a login.)

## Fix

The repo enforces what goose cannot:

- The migration-guard hook (append-only mode for `db/migrations`, from
  `appendOnlyMigrationsDirs` in `.claude/agent-config.json`) refuses Claude's edits to a migration
  a protected branch already has; new files are free.
- `scripts/check/migrations.sh` fails a pull request that changes, deletes or renames a migration
  the base branch has, or adds one with a version at or below the base's newest.

A fix to a merged migration is a new migration.

## When to revisit

If goose starts storing checksums of applied files.
