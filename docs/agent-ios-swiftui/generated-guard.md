# generated-guard

Hook · agent-ios-swiftui · PreToolUse on the write tools · blocks with exit 2 · timeout 10 s · no network · fails closed

## What it does

generated-guard refuses hand edits to the generated API client and the copied OpenAPI spec of an
iOS app: any file or folder listed in `generatedPaths` in `.claude/agent-config.json`.

swift-openapi-generator writes the client from the backend's spec copy, and both are committed. A
hand edit to the client is lost at the next generation, and the quality gate fails the pull
request when the committed client differs from what the spec generates; an edit to the spec copy
makes the app disagree with the API it calls.

## When to reach for it

It runs by itself before `Write`, `Edit`, `MultiEdit` and Serena's write tools. You never call it.
Claude copies the backend's spec again and runs `bash scripts/ios/api-client.sh` instead.

**Not for:** shell writes (`cp`, a redirect), which it lets through on purpose because copying the
spec and running the generator write that way; review generated files in the pull request instead.

## What it blocks

`/agent-ios-swiftui:setup` seeds `generatedPaths` with
`Packages/AppCore/Sources/APIClient/GeneratedSources`, the payload registry beside it
(`PayloadEndpoints.generated.swift`) and the spec copy
(`Packages/AppCore/Sources/APIClient/openapi.json`, and `openapi.yaml`). A path your repo does not
have guards nothing.

| What | Why it is blocked | Do this instead |
| --- | --- | --- |
| `Write`, `Edit` or `MultiEdit` in `GeneratedSources/` | The generator overwrites it, and the gate's drift check fails | Change the backend's spec, copy it, regenerate |
| `Write`, `Edit` or `MultiEdit` on `PayloadEndpoints.generated.swift` | `node scripts/generate/payload-registry.mjs` writes it from the spec and `payload.config.json`, and its check fails a hand edit | Change the exemption in `payload.config.json`, then run the generator |
| `Write`, `Edit` or `MultiEdit` on the spec copy | The copy would drift from the API it describes | Change it in the backend and copy it again |
| Serena's write tools there, including a folder-wide `replace_in_files` that would reach one | Same | Same |
| A payload it cannot read | Fail closed | Fix the cause; `replace_in_files` without python3 is refused |

### How to disable

- **This guard only:** set `"generatedPaths": []` in `.claude/agent-config.json`. An empty list guards nothing.
- **This repo, for you only:** `claude plugin disable agent-ios-swiftui@agent-config-kit --scope local`.
  agent-core keeps running.
- **This repo, for everyone:** the same command with `--scope project` in place of `--scope local`,
  then commit `.claude/settings.json`. Deleting `.claude/agent-config-kit.lock` and
  `.claude/agent-config.json` is no off switch: a machine that saw the repo opted in keeps guarding
  it (the plugin remembers the opt-in) and says so.

### Check it yourself

Run this from a clone of agent-config-kit. `CLAUDE_PLUGIN_ROOT` is unset there, so the opt-in gate
does not apply (a hook runs as if the project had opted in).

```bash
d=$(mktemp -d) && mkdir -p "$d/.claude" \
  && printf '%s' '{"generatedPaths": ["Packages/AppCore/Sources/APIClient/GeneratedSources"]}' >"$d/.claude/agent-config.json" \
  && printf '%s' "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$d/Packages/AppCore/Sources/APIClient/GeneratedSources/Client.swift\"}}" \
  | CLAUDE_PROJECT_DIR="$d" bash plugins/agent-ios-swiftui/scripts/generated-guard.sh; echo "exit=$?"
# expect: exit=2, and on stderr:
# [generated-guard] BLOCKED: Packages/AppCore/Sources/APIClient/GeneratedSources/Client.swift is generated output (Packages/AppCore/Sources/APIClient/GeneratedSources in generatedPaths).
# Change its source and run the project's generator instead of editing it.
```

## Common questions

**Is this the same script as agent-fe-nextjs's guard?**
Yes, byte for byte; only the paths setup seeds differ. A repo uses one stack plugin, so the guard runs once.

**Can a shell command still write a generated file?**
Yes. `cp` and the generator's own writes are not refused, on purpose: that is how the spec arrives and how the client is regenerated.

**Does it need python3?**
No: jq is enough for Write and Edit. Without python3, Serena's `replace_in_files` is refused, because its scope cannot be checked.

## It's working if

- Claude copies the backend's spec and runs `bash scripts/ios/api-client.sh`; the generated files
  change only through that run.
- A direct edit of a generated file or the spec copy is refused with `[generated-guard] BLOCKED:`.

## Where it fits

The one hook of [agent-ios-swiftui](../../plugins/agent-ios-swiftui/README.md). The quality gate checks
the other side: that the committed client is what the committed spec generates.
