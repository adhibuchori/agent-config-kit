# migration-guard

Hook · agent-ai-fastapi · PreToolUse on the write tools · blocks with exit 2 · timeout 10 s · no network · fails closed

## What it does

migration-guard refuses hand edits to generated migrations: files under the folders listed in
`migrationsDirs` in `.claude/agent-config.json`.

A migration that already ran is history. Editing it makes the database, the migration log and the
schema disagree, and the next deploy fails or silently skips the change.

Hand-written migrations (goose, sqlx, golang-migrate) go in `appendOnlyMigrationsDirs` instead,
empty by default. There the guard lets Claude write a new migration and edit one that only the work
branch has, and refuses a write to a file a protected branch already holds: an
[append-only migration](../../CONTEXT.md#append-only-migration) never changes once it merges
([ADR 0007](../adr/0007-hand-written-migrations-are-append-only.md)).

## When to reach for it

It runs by itself before `Write`, `Edit`, `MultiEdit` and Serena's write tools. Claude changes the
schema and generates a new migration with Alembic (`uv run alembic revision --autogenerate`) instead.

**Not for:** a shell edit or delete of a migration; review migrations in the pull request like any
other code instead.

## What it blocks

Defaults for `migrationsDirs`: `src/db/migrations`, `drizzle`, `src/app/db/migrations/versions`,
`alembic/versions`, `migrations/versions`. A folder your repo does not have guards nothing, so the
hook switches itself off in a repo without migrations.

| What | Why it is blocked | Do this instead |
| --- | --- | --- |
| `Write`, `Edit` or `MultiEdit` on a file under a `migrationsDirs` folder | The migration may already have run somewhere | Change the schema and generate a new migration |
| Serena's write tools there, including a folder-wide `replace_in_files` | Same | Same |
| A write to a file under an `appendOnlyMigrationsDirs` folder that a `protectedBranches` branch (local, or `origin/<branch>` as last fetched) already has | A database may have run it | Write a new migration that changes what this one did |
| A folder-wide `replace_in_files` that reaches an `appendOnlyMigrationsDirs` folder | It could rewrite a merged migration | Narrow `relative_path`, or add `paths_exclude_glob` |
| A payload it cannot read, or a repo where git cannot say whether a protected branch has the file | Fail closed | Fix the cause; `replace_in_files` without python3 is refused |

### How to disable

- **This guard only:** set `"migrationsDirs": []`, and leave `appendOnlyMigrationsDirs` empty, in `.claude/agent-config.json`. Empty lists turn the guard off in a repo that has migrations.
- **This repo, for you only:** `claude plugin disable agent-ai-fastapi@agent-config-kit --scope local`.
  agent-core keeps running.
- **This repo, for everyone:** the same command with `--scope project` in place of `--scope local`,
  then commit `.claude/settings.json`. Deleting `.claude/agent-config-kit.lock` and
  `.claude/agent-config.json` is no off switch: a machine that saw the repo opted in keeps guarding
  it (the plugin remembers the opt-in) and says so.

### Check it yourself

Run this from a clone of agent-config-kit. `CLAUDE_PLUGIN_ROOT` is unset there, so the opt-in gate
does not apply (a hook runs as if the project had opted in).

```bash
d=$(mktemp -d) && mkdir -p "$d/alembic/versions" \
  && printf '%s' "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$d/alembic/versions/0001_init.py\",\"content\":\"--\"}}" \
  | CLAUDE_PROJECT_DIR="$d" bash plugins/agent-ai-fastapi/scripts/migration-guard.sh; echo "exit=$?"
# expect: exit=2, and on stderr:
# [migration-guard] BLOCKED: alembic/versions/0001_init.py is a generated migration (alembic/versions in migrationsDirs).
# Generate a new migration with the project's tool instead of editing this one.
```

## Common questions

**Why does the example create a temp folder?**
A folder the repo does not have guards nothing, and this repository has no `alembic/versions/`.

**Can Claude still delete a migration with `rm`?**
safety-check refuses recursive deletes of protected paths; a single-file shell edit is not this guard's job. Review migrations in the pull request like any other code.

## It's working if

- For a schema change, Claude runs `uv run alembic revision --autogenerate`, and `git diff` shows
  no change to an existing revision.
- An edit to an existing migration is refused with `[migration-guard] BLOCKED:`.

## Where it fits

The one hook of [agent-ai-fastapi](../../plugins/agent-ai-fastapi/README.md). The CI quality gate checks the
other side: that the schema and the committed migrations agree.
