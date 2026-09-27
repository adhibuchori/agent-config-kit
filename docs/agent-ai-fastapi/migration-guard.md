# migration-guard

Hook · agent-ai-fastapi · PreToolUse on the write tools · blocks with exit 2 · timeout 10 s · no network · fails closed

## What it does

migration-guard refuses hand edits to generated migrations: files under the folders listed in
`migrationsDirs` in `.claude/agent-config.json`.

A migration that already ran is history. Editing it makes the database, the migration log and the
schema disagree, and the next deploy fails or silently skips the change.

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
| A payload it cannot read | Fail closed | Fix the cause; `replace_in_files` without python3 is refused |

### How to disable

- **This guard only:** set `"migrationsDirs": []` in `.claude/agent-config.json`. An empty list turns the guard off in a repo that has migrations.
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
