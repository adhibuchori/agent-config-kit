# generated-guard

Hook · agent-be-go · PreToolUse on the write tools · blocks with exit 2 · timeout 10 s · no network · fails closed

## What it does

generated-guard refuses hand edits to generated output: the server oapi-codegen writes, sqlc's
query code and the exported OpenAPI contract, listed in `generatedPaths` in
`.claude/agent-config.json` (setup seeds `api/openapi.json`, `internal/httpapi/api.gen.go` and
`internal/postgres/db`).

A hand edit there is lost at the next generation, or quietly disagrees with the spec or the SQL it
came from, and the gate's drift check then fails the pull request.

## When to reach for it

It runs by itself before `Write`, `Edit`, `MultiEdit` and Serena's write tools. Claude changes
`api/openapi.yaml` or the SQL in `db/queries/` and runs `bash scripts/check/generated.sh --write`
instead.

**Not for:** the generators' own writes through the shell, which it lets through on purpose.

## What it blocks

This plugin ships the same `generated-guard.sh` as agent-fe-nextjs and agent-docs-nextra. With
agent-core's shared scripts at the release that adds Go's marker, it also refuses any file whose
header says `// Code generated ... DO NOT EDIT.`, wherever it lives.

| What | Why it is blocked | Do this instead |
| --- | --- | --- |
| `Write`, `Edit` or `MultiEdit` on a path under `generatedPaths` | The generator would overwrite the edit | Change the spec or the SQL, then regenerate |
| Serena's write tools on such a path, including a folder-wide `replace_in_files` | Same | Same |
| A payload it cannot read | Fail closed | Fix the cause; `replace_in_files` without python3 is refused |

### How to disable

- **This guard only:** set `"generatedPaths": []` in `.claude/agent-config.json`.
- **This repo, for you only:** `claude plugin disable agent-be-go@agent-config-kit --scope local`.
  agent-core keeps running.
- **This repo, for everyone:** the same command with `--scope project` in place of `--scope local`,
  then commit `.claude/settings.json`.

### Check it yourself

In a repo set up with this plugin:

```bash
printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"internal/httpapi/api.gen.go","old_string":"a","new_string":"b"}}' \
  | CLAUDE_PROJECT_DIR="$PWD" bash "<plugin folder>/scripts/generated-guard.sh"; echo "exit=$?"
# expect: exit=2 and a "[generated-guard] BLOCKED: internal/httpapi/api.gen.go is generated output" line
```

## Common questions

**The spec is `api/openapi.yaml`; is that guarded too?**
No. The YAML is the contract you edit; `api/openapi.json` is its export, generated from it.

**sqlc writes somewhere else in my repo.**
List that folder in `generatedPaths`, with every default you still want: a key you set replaces the
defaults whole.

## It's working if

- Claude edits `api/openapi.yaml` or `db/queries/`, regenerates, and the generated files change only
  through that run.
- A direct edit of a generated file is refused with `[generated-guard] BLOCKED:`.

## Where it fits

One of the two hooks of [agent-be-go](../../plugins/agent-be-go/README.md), with
[migration-guard](migration-guard.md). `scripts/check/generated.sh` checks the same files in the
gate: it regenerates them in a scratch copy and fails on any difference.
