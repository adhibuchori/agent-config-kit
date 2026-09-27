#!/usr/bin/env bash
# SessionStart (plugin mode): says when this project's setup is missing or older than the installed
# agent-core, so Claude can point the user at /agent-core:setup or /agent-core:sync. It reads two
# small JSON files and compares versions: no hashing, no git, well under a second. It never writes.
#
#   .claude/agent-config.json but no .claude/agent-config-kit.lock   setup has not run here
#   a lock without an agent-core entry                                setup has not run for core
#   a lock whose agent-core version differs from this plugin's       sync has not run since the update
#
# The full comparison (every file, block, settings entry and alias) is `agent-sync check`, which
# /agent-core:sync --check runs. Wired with `|| true`, and it goes through the project gate like
# every other hook: a project that has not opted in hears nothing. Fails open: without python3 and
# jq, or with a lock it cannot read, it says nothing.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hook_start feedback "[setup-check]"

PLUGIN_JSON="$(dirname "${BASH_SOURCE[0]}")/../.claude-plugin/plugin.json"
LOCK="$ROOT/.claude/agent-config-kit.lock"
[[ -f "$PLUGIN_JSON" ]] || exit 0
# The gate already stops a project with neither file in plugin mode; run by hand, so does this.
[[ -f "$ROOT/.claude/agent-config.json" || -f "$LOCK" ]] || exit 0

# $1 file, $2 jq path, $3 the same path as python keys separated by dots.
json_get() {
  if command -v jq &>/dev/null; then
    jq -r "$2 // empty" "$1" 2>/dev/null
  elif command -v python3 &>/dev/null; then
    hook_py -c '
import json, sys
node = json.load(open(sys.argv[1], encoding="utf-8"))
for key in sys.argv[2].split("."):
    node = node.get(key) if isinstance(node, dict) else None
print(node if isinstance(node, str) else "")' "$1" "$3" 2>/dev/null
  fi
}

MINE="$(json_get "$PLUGIN_JSON" '.version' version)"
[[ -n "$MINE" ]] || exit 0

if [[ ! -f "$LOCK" ]]; then
  report "agent-core: .claude/agent-config.json opts this project into the agent-config-kit hooks, but setup has not run here, so the permissions, rules, check scripts and the unlock and .env helpers are missing. Suggest /agent-core:setup to the user (or the stack plugin's own setup, which includes agent-core's)." SessionStart
  exit 0
fi

LOCKED="$(json_get "$LOCK" '.plugins["agent-core"].version' plugins.agent-core.version)"
if [[ -z "$LOCKED" ]]; then
  report "agent-core: .claude/agent-config-kit.lock has no agent-core entry, so agent-core's setup has not run in this project. Suggest /agent-core:setup to the user." SessionStart
elif [[ "$LOCKED" != "$MINE" ]]; then
  report "agent-core: this project was set up with agent-core $LOCKED, and $MINE is installed. Suggest /agent-core:sync to the user: it shows what changed and writes only after they approve." SessionStart
fi
exit 0
