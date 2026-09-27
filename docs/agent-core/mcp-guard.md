# mcp-guard

Hook · agent-core · PreToolUse on GitHub MCP writes · blocks with exit 2 · timeout 10 s · no network · fails closed

## What it does

mcp-guard stops the GitHub MCP tools from writing straight onto a protected branch: `push_files`,
`create_or_update_file`, `delete_file` and `create_branch` with a `branch` in `protectedBranches`.

Those tools commit without a shell command, so [safety-check](safety-check.md) never sees them.

## When to reach for it

It runs by itself before those four GitHub MCP tools, from any MCP server whose name contains
`github`. You never call it. Work reaches a protected branch through a pull request
(`/agent-core:create-pr`, then `/agent-core:merge-pr`).

**Not for:** a `git push` from the shell; [safety-check](safety-check.md) guards that instead.

## What it blocks

The protected list is `protectedBranches` in `.claude/agent-config.json`, the same list
safety-check uses.

| What | Why it is blocked | Do this instead |
| --- | --- | --- |
| `push_files`, `create_or_update_file`, `delete_file` onto `dev`, `prod`, `main` or `master` | It skips review and CI | Write to a work branch and open a PR |
| `create_branch` named like a protected branch | It would create or reset a shared branch | Pick a work branch name, such as `internal/<scope>` |
| A payload it cannot read, or a branch list it cannot load | Fail closed | Fix the payload or `.claude/agent-config.json` |

### How to disable

- **One rule:** most rules take a setting in `.claude/agent-config.json` (listed above the table
  or in [agent-core's configuration](../../plugins/agent-core/README.md#configuration)). A key you set
  replaces its default whole, so list the defaults you still want.
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
printf '%s' '{"tool_name":"mcp__github__push_files","tool_input":{"owner":"o","repo":"r","branch":"main","files":[],"message":"wip"}}' \
  | CLAUDE_PROJECT_DIR="$PWD" bash plugins/agent-core/scripts/mcp-guard.sh; echo "exit=$?"
# expect: exit=2, and on stderr:
# [mcp-guard] BLOCKED: push_files writes straight to the protected branch main. Push your work
# branch and open a PR.
```

## Common questions

**Does it need python3?**
No. It reads the payload with jq or python3, whichever exists.

**Our GitHub server has a custom name.**
The matcher is `mcp__.*github.*__(push_files|create_or_update_file|delete_file|create_branch)`, so any server name that contains `github` is covered.

## It's working if

- A `push_files` to `feat/login` goes through.
- The same call to `main` is refused with `[mcp-guard] BLOCKED:`.

## Where it fits

The MCP twin of [safety-check](safety-check.md)'s protected-branch rule, in
[agent-core](../../plugins/agent-core/README.md).
