# 7. A hand-written migration is append-only once a protected branch has it

- Status: accepted
- Date: 2026-10-11

## Context

migration-guard refuses every hand edit under `migrationsDirs`, because drizzle-kit and Alembic
write those files: the fix is to change the schema and generate again. goose, sqlx and
golang-migrate have no generator. A person writes each migration, and keeps editing it while the
change is on a work branch. The same refusal there would block normal work. Letting every edit
through is no better: goose never notices that an applied migration changed, and sqlx refuses to
run once a checksum differs, so an edit to a migration a database already ran leaves that database
and the files disagreeing with nothing to say so.

The line a person can see is the merge. Once a protected branch has the file, a deploy or a
teammate's database may have run it.

## Decision

- A second folder list, `appendOnlyMigrationsDirs` in `.claude/agent-config.json`, empty by
  default; a stack's setup seeds it (`db/migrations`, `migrations`).
- migration-guard lets Claude write a new file there, and edit a file that only the work branch
  has. It refuses a write to a file that any of `protectedBranches` already holds, as a local branch
  or as `origin/<branch>` from the last fetch. The fix is a new migration that changes what the old
  one did.
- When git cannot answer (not a repo, a branch list it cannot read), the guard refuses, as every
  guard fails closed. A repo with no commit yet has nothing merged.
- CI holds the same line against the pull request's base: a migration the base has may not be
  modified, deleted or renamed, and a new one sorts after every migration the base has.

## Consequences

- Hand-written migrations stay free to change until they merge, and never change after.
- The guard trusts the protected branches it can see. A branch fetched long ago, or a database run
  from an unmerged branch, is outside what it knows; CI's check against the base is the backstop.
- A data fix to a merged migration is a new migration, even for a typo, so a database that ran the
  old one and one that did not end up the same.
