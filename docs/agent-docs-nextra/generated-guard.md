# generated-guard

Hook · agent-docs-nextra · PreToolUse on the write tools · blocks with exit 2 · timeout 10 s · no network · fails closed

## What it does

generated-guard refuses hand edits to generated output: any file or folder listed in
`generatedPaths` in `.claude/agent-config.json`.

In a docs site that is the API reference and changelog pages your generators write, and the OpenAPI contract copied from the service. A hand edit there is lost at the next generation, or quietly disagrees with its source.

## When to reach for it

It runs by itself before `Write`, `Edit`, `MultiEdit` and Serena's write tools. You never call it.
Claude changes the source and runs your generator instead.

**Not for:** shell writes (a redirect, `sed -i`, `cp`), which it lets through on purpose because
your generator writes that way; review generated files in the pull request instead.

## What it blocks

Defaults for `generatedPaths`: `src/lib/api/generated`, `src/generated`, `openapi.json`, `openapi.yaml`, `openapi.yml`; setup's `generated-pages` question can set `content/technical` and `content/changelog.mdx` instead. A key you set replaces the defaults whole. A
path your repo does not have guards nothing.

| What | Why it is blocked | Do this instead |
| --- | --- | --- |
| `Write`, `Edit` or `MultiEdit` on a path under `generatedPaths` | The generator would overwrite the edit, or the copy would drift from its source | Change the source and run the generator |
| Serena's write tools on such a path, including a folder-wide `replace_in_files` that would reach one | Same | Same |
| A payload it cannot read | Fail closed | Fix the cause; `replace_in_files` without python3 is refused |

### How to disable

- **This guard only:** set `"generatedPaths": []` in `.claude/agent-config.json`. An empty list guards nothing.
- **This repo, for you only:** `claude plugin disable agent-docs-nextra@agent-config-kit --scope local`.
  agent-core keeps running.
- **This repo, for everyone:** the same command with `--scope project` in place of `--scope local`,
  then commit `.claude/settings.json`. Deleting `.claude/agent-config-kit.lock` and
  `.claude/agent-config.json` is no off switch: a machine that saw the repo opted in keeps guarding
  it (the plugin remembers the opt-in) and says so.

### Check it yourself

Run this from a clone of agent-config-kit. `CLAUDE_PLUGIN_ROOT` is unset there, so the opt-in gate
does not apply (a hook runs as if the project had opted in).

```bash
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"openapi.json","content":"{}"}}' \
  | CLAUDE_PROJECT_DIR="$PWD" bash plugins/agent-docs-nextra/scripts/generated-guard.sh; echo "exit=$?"
# expect: exit=2, and on stderr:
# [generated-guard] BLOCKED: openapi.json is the API contract, copied from the service that owns it.
# Change it there and copy it again; never edit the copy.
```

## Common questions

**Can a shell command still write a generated file?**
Yes. A redirect, `sed -i` or `cp` is not refused by this guard or by safety-check, on purpose: your generator itself writes those files through the shell.

**My generator writes somewhere else.**
List your paths in `generatedPaths`, for example `["src/gen", "openapi.json"]`. Include every default you still want.

**Does it need python3?**
No: jq is enough for Write and Edit. Without python3, Serena's `replace_in_files` is refused, because its scope cannot be checked.

## It's working if

- Claude edits the generator's input and runs the generator; the generated file changes only
  through that run.
- A direct edit of a generated file is refused with `[generated-guard] BLOCKED:`.

## Where it fits

The one hook of [agent-docs-nextra](../../plugins/agent-docs-nextra/README.md). It sits next to agent-core's
[safety-check](../agent-core/safety-check.md), which covers shell commands.
