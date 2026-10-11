# migration-guard

Hook · agent-be-axum · PreToolUse on the write tools · blocks with exit 2 · timeout 10 s · no network · fails closed

## What it does

migration-guard keeps hand-written sqlx migrations append-only: a file under a folder listed in
`appendOnlyMigrationsDirs` is refused once a protected branch already has it.

sqlx checksums every applied migration, so any byte changed in a file a database ran fails every
later deploy ("previously applied but has been modified"). A new migration is yours to write and
rewrite until it merges; after that, a change to the schema is a new file.

## When to reach for it

It runs by itself before `Write`, `Edit`, `MultiEdit` and Serena's write tools. Claude writes a
new migration with `sqlx migrate add <name>` instead, as the `db-migration` skill walks through.

**Not for:** a shell edit of a migration, or a rebase that reorders versions; CI's
`scripts/check/migrations.sh --base` checks both sides of the pull request instead.

## What it blocks

`/agent-be-axum:setup` writes `"appendOnlyMigrationsDirs": ["migrations"]` into
`.claude/agent-config.json` when the service owns its schema. The protected branches are
agent-core's `protectedBranches` (`dev`, `prod`, `main`, `master`), local or as last fetched from
`origin`. A folder your repo does not have guards nothing.

| What | Why it is blocked | Do this instead |
| --- | --- | --- |
| `Write`, `Edit` or `MultiEdit` on a migration a protected branch has | A database may have run it, and sqlx refuses a changed checksum | Write a new migration that changes what this one did |
| Serena's write tools there, including a folder-wide `replace_in_files` | Same | Same |
| A file in such a folder when git cannot say whether a protected branch has it | Fail closed | Fix the repository, then retry |
| A payload it cannot read | Fail closed | Fix the cause; `replace_in_files` without python3 is refused |

### How to disable

- **This guard only:** set `"appendOnlyMigrationsDirs": []` in `.claude/agent-config.json`.
- **This repo, for you only:** `claude plugin disable agent-be-axum@agent-config-kit --scope local`.
  agent-core keeps running.
- **This repo, for everyone:** the same command with `--scope project` in place of `--scope local`,
  then commit `.claude/settings.json`. Deleting `.claude/agent-config-kit.lock` and
  `.claude/agent-config.json` is no off switch: a machine that saw the repo opted in keeps guarding
  it (the plugin remembers the opt-in) and says so.

### Check it yourself

Run this from a clone of agent-config-kit. `CLAUDE_PLUGIN_ROOT` is unset there, so the opt-in gate
does not apply (a hook runs as if the project had opted in).

```bash
d=$(mktemp -d) && git -C "$d" init -q -b main && mkdir -p "$d/migrations" "$d/.claude" \
  && printf '%s\n' '{"appendOnlyMigrationsDirs": ["migrations"]}' >"$d/.claude/agent-config.json" \
  && printf 'select 1;\n' >"$d/migrations/20261011000000_init.sql" \
  && git -C "$d" add -A && git -C "$d" -c user.name=t -c user.email=t@example.invalid commit -qm init \
  && printf '%s' "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$d/migrations/20261011000000_init.sql\"}}" \
  | CLAUDE_PROJECT_DIR="$d" bash plugins/agent-be-axum/scripts/migration-guard.sh; echo "exit=$?"
# expect: exit=2, and on stderr:
# [migration-guard] BLOCKED: migrations/20261011000000_init.sql is already on main, so a database may have run it.
# Write a new migration that changes what this one did; a merged migration never changes.
```

## Common questions

**Can I still fix a migration on my branch?**
Yes. Until a protected branch has the file, every edit is allowed; that is where a migration is
reviewed and corrected.

**What about the `.sqlx/` query cache?**
[generated-guard](generated-guard.md) refuses hand edits there; `cargo sqlx prepare` rewrites it.

## It's working if

- For a schema change, Claude adds a new `migrations/<version>_<name>.sql`, and `git diff` shows no
  change to a migration `main` already has.
- An edit to a merged migration is refused with `[migration-guard] BLOCKED:`.

## Where it fits

One of the two hooks of [agent-be-axum](../../plugins/agent-be-axum/README.md), next to
[generated-guard](generated-guard.md). The CI quality gate checks the other side: no migration the
base has changed, and every new version above the base's highest.
