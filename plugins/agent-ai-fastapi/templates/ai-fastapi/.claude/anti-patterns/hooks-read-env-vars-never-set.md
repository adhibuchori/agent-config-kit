# A hook that reads `CLAUDE_TOOL_INPUT_*` never fires

**Applies to:** every Claude Code hook script: the kit's (in the agent-config-kit plugins) and any
of your own in `.claude/hooks/`
**Status:** Permanent (Claude Code's hook contract); `scripts/check/ai-config.sh` refuses the
variables

## Symptom

The hooks are wired (in a plugin's `hooks/hooks.json` or in `.claude/settings.json`), every one
exits 0, and nothing they promise happens: the formatter never formats, the guard never blocks.
Nothing errors, so the layer looks healthy for as long as nobody tests it by its effect. A hook
layer can stay inert for months this way.

## Root cause

Two wrong assumptions about the contract, each silent on its own:

1. **Input.** Claude Code passes the tool call as JSON on **stdin** (`tool_name`,
   `tool_input.command`, `tool_input.file_path`, ...). It never sets `CLAUDE_TOOL_INPUT_COMMAND`
   or `CLAUDE_TOOL_INPUT_FILE_PATH`. A hook that reads them sees empty strings, matches nothing and
   exits 0.
2. **Blocking.** Only exit **2** blocks a PreToolUse call, and its stderr is the reason Claude
   reads. Exit 1 is a non-blocking error: the call goes through. A guard that ends in `exit 1`
   "blocks" in its author's shell and in no session.

A third, quieter one: PostToolUse stdout is only logged. A finding reaches Claude only as
`hookSpecificOutput.additionalContext` JSON.

## Fix

Read stdin once and parse it with python3 (or jq), block with exit 2 and a reason on stderr, and
report PostToolUse findings as `additionalContext`. agent-core's `scripts/lib.sh` does all three
(`hook_field`, `block`, `report`), so a new hook sources a copy of it rather than reimplementing
them. `scripts/check/ai-config.sh` fails when a hook script reads `CLAUDE_TOOL_INPUT_*`.

## Verification

Pipe the payload and read the exit code. The kit's hooks sit in the installed agent-core plugin;
run from your own shell, they skip the plugin's opt-in check:

```bash
CACHE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/agent-config-kit"
KIT="$(ls -d "$CACHE"/agent-core/*/ | tail -n 1)"
printf '{"tool_name":"Bash","tool_input":{"command":"git push origin dev"}}' \
  | bash "$KIT/scripts/safety-check.sh"; echo "exit $?"   # the refusal on stderr, then exit 2
```

The variable style does nothing: `CLAUDE_TOOL_INPUT_FILE_PATH=<file> bash
"$KIT/scripts/post-edit.sh" </dev/null` exits 0 and leaves the file as it was.
`scripts/check/hook-probes.sh` (with `HOOKS_DIR="$KIT/scripts"`) pipes a payload of each kind —
one the rule must stop and one it must let through — for every rule, so a new rule adds both.

## Scope

Every Claude Code hook. There is nothing upstream to wait for: this is the contract, not a bug.
