# generated-guard

Hook · agent-be-axum · PreToolUse on the write tools · blocks with exit 2 · timeout 10 s · no network · fails closed

## What it does

generated-guard refuses hand edits to generated output: any file or folder listed in
`generatedPaths` in `.claude/agent-config.json`.

In a Rust + Axum service that is the sqlx query cache in `.sqlx/`, which `cargo sqlx prepare` writes
and the offline build reads, and `openapi.json`, which `cargo run --bin openapi` writes from the
handlers. A hand edit there either makes the build check a query against stale data or makes the
spec drift test fail.

## When to reach for it

It runs by itself before `Write`, `Edit`, `MultiEdit` and Serena's write tools. You never call it.
Claude changes the source (the query, the handler) and runs the generator instead.

**Not for:** shell writes (a redirect, `cargo sqlx prepare` itself), which it lets through on
purpose because the generators write that way; review generated files in the pull request instead.

## What it blocks

`/agent-be-axum:setup` writes `"generatedPaths": [".sqlx", "openapi.json"]` when the service owns
its schema; without that file the defaults apply (`src/lib/api/generated`, `src/generated`,
`openapi.json`, `openapi.yaml`, `openapi.yml`). A key you set replaces the defaults whole. A path
your repo does not have guards nothing.

| What | Why it is blocked | Do this instead |
| --- | --- | --- |
| `Write`, `Edit` or `MultiEdit` on a path under `generatedPaths` | The generator would overwrite the edit, or the copy would drift from its source | Change the source and run the generator |
| Serena's write tools on such a path, including a folder-wide `replace_in_files` that would reach one | Same | Same |
| A payload it cannot read | Fail closed | Fix the cause; `replace_in_files` without python3 is refused |

### How to disable

- **This guard only:** set `"generatedPaths": []` in `.claude/agent-config.json`. An empty list guards nothing.
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
d=$(mktemp -d) && mkdir -p "$d/.sqlx" "$d/.claude" \
  && printf '%s\n' '{"generatedPaths": [".sqlx", "openapi.json"]}' >"$d/.claude/agent-config.json" \
  && printf '%s' "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$d/.sqlx/query-0a1b.json\",\"old_string\":\"a\",\"new_string\":\"b\"}}" \
  | CLAUDE_PROJECT_DIR="$d" bash plugins/agent-be-axum/scripts/generated-guard.sh; echo "exit=$?"
# expect: exit=2, and on stderr:
# [generated-guard] BLOCKED: .sqlx/query-0a1b.json is generated output (.sqlx in generatedPaths).
# Change its source and run the project's generator instead of editing it.
```

## Common questions

**Can a shell command still write a generated file?**
Yes, on purpose: `cargo sqlx prepare` and the spec export write those files through the shell.

**Why is `openapi.json` called a copied contract in the message?**
The guard is shared with the frontend plugins, where `openapi.json` is copied from a backend. Here
it is generated: regenerate it with `cargo run --locked --quiet --bin openapi`.

## It's working if

- Claude edits a query or a handler and runs the generator; the generated file changes only through
  that run.
- A direct edit of a generated file is refused with `[generated-guard] BLOCKED:`.

## Where it fits

One of the two hooks of [agent-be-axum](../../plugins/agent-be-axum/README.md), next to
[migration-guard](migration-guard.md). It sits beside agent-core's
[safety-check](../agent-core/safety-check.md), which covers shell commands.
