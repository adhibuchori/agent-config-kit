# db-guard

Hook · agent-core · PreToolUse on `mcp__.*` · blocks with exit 2 · timeout 10 s · no network · fails closed

## What it does

db-guard lets one read-only SQL statement reach the production database and holds every write
until you unlock `db`.

It checks only the tool named by `dbWriteGuard.toolPattern` in `.claude/agent-config.json` (default
`mcp__db-prod__execute_sql`); any other MCP tool passes. Reads are one `SELECT`, `SHOW`, `VALUES`,
`TABLE`, `DESCRIBE`, `EXPLAIN` or `WITH … SELECT`. Everything else counts as a write: several
statements, a comment that could hide one, quoting that databases read differently, and SQL it
cannot parse.

## When to reach for it

It runs by itself before every MCP tool call in an opted-in repo, and acts only on the production
SQL tool. When Claude needs a write, it asks you to open the lock:

```text
! bun unlock db
```

The lock closes by itself after 15 minutes (`! bun unlock off` closes it now).

**Not for:** keeping production read-only on its own, since a `SELECT` that calls a writing
function looks like a read; use the `db-prod` server started read-only
(`--access-mode=restricted`) for that.

## What it blocks

Its matcher is `mcp__.*` because you cannot edit a plugin's matcher; the script filters by
`toolPattern` itself. jq reads the tool name and bash matches it, so a call to any other tool passes
without python3. **Without python3 every call to the SQL tool is refused in an opted-in repo**,
reads included, and so is every MCP call when `toolPattern` uses more than plain names, `|` and
`( )`.

| What | Why it is blocked | Do this instead |
| --- | --- | --- |
| `INSERT`, `UPDATE`, `DELETE`, `MERGE`, DDL (`CREATE`, `ALTER`, `DROP`, `TRUNCATE`) | They change production data | `! bun unlock db`, or run the statement yourself |
| A write hidden in a read: a data-modifying CTE, `SELECT … INTO`, `FOR UPDATE` | They write although they start with `SELECT` | Same as above |
| Built-in functions that change state or reach outside (`setval`, `pg_terminate_backend`, `dblink`, `pg_read_file`) | They act on the server, not only read rows | Same as above |
| Several statements, `SET ROLE`, comments holding a `;`, dollar quotes, backticks, a backslash that splits a string | Each could smuggle a second statement past a reader | Send one plain statement |
| SQL it cannot parse, a payload it cannot read, or no python3 | Fail closed | Fix the SQL or install python3 |

### How to disable

- **Point it elsewhere:** set `"dbWriteGuard": {"toolPattern": "<regex>"}` in
  `.claude/agent-config.json` to guard a differently named SQL tool.
- **Keep the database read-only instead:** the `db-prod` server in the kit's `.mcp.json` starts with
  `--access-mode=restricted`, so the server itself refuses writes and `unlock db` changes nothing.
- **This repo, for you only:** disable the plugins at local scope. A stack plugin depends on
  agent-core, so disable it first:

  ```bash
  claude plugin disable agent-fe-nextjs@agent-config-kit --scope local   # your stack plugin
  claude plugin disable agent-core@agent-config-kit --scope local
  ```

- **Everywhere:** the same two commands without `--scope local`.
- **This repo, for everyone:** the same commands with `--scope project` in place of `--scope local`,
  then commit `.claude/settings.json`. Deleting `.claude/agent-config-kit.lock` and
  `.claude/agent-config.json` is no off switch: a machine that saw the repo opted in keeps guarding
  it (the plugin remembers the opt-in) and says so.

### Check it yourself

Run this from a clone of agent-config-kit. `CLAUDE_PLUGIN_ROOT` is unset there, so the opt-in gate
does not apply (a hook runs as if the project had opted in).

```bash
printf '%s' '{"tool_name":"mcp__db-prod__execute_sql","tool_input":{"sql":"DELETE FROM users"}}' \
  | CLAUDE_PROJECT_DIR="$PWD" bash plugins/agent-core/scripts/db-guard.sh; echo "exit=$?"
# expect: exit=2, and on stderr:
# [db-guard] BLOCKED: this SQL may change the production database (a DELETE statement). Reads (one
# SELECT, SHOW, VALUES, EXPLAIN, or WITH ... SELECT) pass. For a write, the user runs
# `! ./scripts/ops/unlock.sh db` themselves and you try again, or you hand them the statement to run.
```

## Common questions

**Why does it name `./scripts/ops/unlock.sh` and not `bun unlock`?**
It names the form your repo supports: the package-manager form when `package.json` has the `unlock` script, the script path otherwise. This repo has no `package.json`.

**Can a `SELECT` still write?**
A `SELECT` that calls a function of your own which writes looks like a read. That is why the kit's production server starts read-only (`--access-mode=restricted`): the server is the layer below this hook.

**The SQL tool is refused with "db-guard reads SQL with python3, which is not installed".**
Install python3 3.8 or newer. db-guard fails closed on its own tool; other MCP tools pass unless
`toolPattern` uses more than plain names, `|` and `( )`.

## It's working if

- `SELECT count(*) FROM users` through the production SQL tool runs.
- `DELETE FROM users` is refused until you run `! bun unlock db`, and runs once it is open.
- `! bun unlock status` shows `db` open with the time it closes.

## Where it fits

Part of [agent-core](../../plugins/agent-core/README.md) and of the [unlock](../unlock.md)
mechanism, next to [safety-check](safety-check.md), which refuses Claude running the unlock itself.
`/agent-core:promote` hands production migrations to you as `!` commands for the same reason.
