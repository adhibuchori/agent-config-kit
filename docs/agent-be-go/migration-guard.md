# migration-guard

Hook · agent-be-go · PreToolUse on the write tools · blocks with exit 2 · timeout 10 s · no network · fails closed

## What it does

migration-guard refuses Claude's edits to a goose migration that a protected branch already has:
files under the folders listed in `appendOnlyMigrationsDirs` in `.claude/agent-config.json`
(setup seeds `db/migrations`). A new migration file is free to write.

goose records only version numbers, so an edited migration that already ran is never noticed: the
database, the migration log and the schema quietly disagree. A change to the schema is a new file.

## When to reach for it

It runs by itself before `Write`, `Edit`, `MultiEdit` and Serena's write tools. Claude writes a new
migration (`go tool goose -dir db/migrations create <name> sql`) instead of editing a merged one;
the [db-migration](db-migration.md) skill walks through it.

**Not for:** a shell edit of a migration, or one that only exists on your branch; the pull
request's gate (`scripts/check/migrations.sh`) compares every migration with the base branch.

## What it blocks

This plugin ships the same `migration-guard.sh` as agent-be-hono and agent-ai-fastapi. Its
append-only mode needs agent-core's shared scripts at the release that introduces
`appendOnlyMigrationsDirs`; with an older copy the key is ignored and the guard stays silent in
`db/migrations`.

| What | Why it is blocked | Do this instead |
| --- | --- | --- |
| `Write`, `Edit` or `MultiEdit` on a file in an append-only folder that a protected branch (local or `origin/`) already holds | A database may have run it | Write a new migration that changes what this one did |
| Serena's write tools there, including a folder-wide `replace_in_files` that reaches one | Same | Same |
| A payload it cannot read, or git that cannot answer | Fail closed | Fix the cause |

### How to disable

- **This guard only:** set `"appendOnlyMigrationsDirs": []` in `.claude/agent-config.json`.
- **This repo, for you only:** `claude plugin disable agent-be-go@agent-config-kit --scope local`.
  agent-core keeps running.
- **This repo, for everyone:** the same command with `--scope project` in place of `--scope local`,
  then commit `.claude/settings.json`. Deleting `.claude/agent-config-kit.lock` and
  `.claude/agent-config.json` is no off switch: a machine that saw the repo opted in keeps guarding
  it (the plugin remembers the opt-in) and says so.

### Check it yourself

In a repo set up with this plugin, where `main` already holds `db/migrations/00001_init.sql`:

```bash
printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"db/migrations/00001_init.sql","old_string":"a","new_string":"b"}}' \
  | CLAUDE_PROJECT_DIR="$PWD" bash "<plugin folder>/scripts/migration-guard.sh"; echo "exit=$?"
# expect: exit=2 and a "[migration-guard] BLOCKED: db/migrations/00001_init.sql is already on main" line
```

## Common questions

**I need to fix a migration that is only on my branch.**
Edit it: the guard refuses only files a protected branch already holds. The gate still checks the
versions against the base branch.

**Can Claude still change a migration with the shell?**
The guard reads Claude's file tools. The pull request's gate fails a changed, deleted or renamed
migration whatever wrote it.

## It's working if

- For a schema change, Claude adds a new file under `db/migrations`, and `git diff` shows no change
  to an existing one.
- An edit to a merged migration is refused with `[migration-guard] BLOCKED:`.

## Where it fits

One of the two hooks of [agent-be-go](../../plugins/agent-be-go/README.md), with
[generated-guard](generated-guard.md). The CI quality gate checks the same rule against the base
branch.
