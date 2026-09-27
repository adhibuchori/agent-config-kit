# shellcheck shell=bash
# Shared setup for the agent-docs-nextra tests. Every test builds its own git repo under
# $BATS_TEST_TMPDIR from the toy site in tests/fixtures/docs-nextra, and none needs the network.

bats_require_minimum_version 1.5.0

DN_REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
DN_PLUGIN="$DN_REPO/plugins/agent-docs-nextra"
DN_GUARD="$DN_PLUGIN/scripts/generated-guard.sh"
DN_TEMPLATES="$DN_PLUGIN/templates"
DN_STACK="$DN_TEMPLATES/docs-nextra"
DN_FIXTURE="$DN_REPO/tests/fixtures/docs-nextra"
DN_CORE="$DN_REPO/plugins/agent-core"
export DN_REPO DN_PLUGIN DN_GUARD DN_TEMPLATES DN_STACK DN_FIXTURE DN_CORE

# git with a fixed identity and no user config, so a test never depends on the machine.
dn_git() {
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -c user.name=probe \
    -c user.email=probe@example.invalid -c init.defaultBranch=main "$@"
}

# A committed copy of the toy site on a work branch; prints its physical path. $1 names the folder.
dn_site() {
  local dir="$BATS_TEST_TMPDIR/${1:-site}"
  mkdir -p "$dir"
  cp -R "$DN_FIXTURE/." "$dir/"
  printf 'node_modules/\n' >"$dir/.gitignore"
  dn_git -C "$dir" init -q
  dn_git -C "$dir" checkout -q -b internal/probe
  dn_git -C "$dir" add -A
  dn_git -C "$dir" commit -q -m fixture
  (cd "$dir" && pwd -P)
}

# The opt-in the hooks check in plugin mode: an empty agent-config.json, or a lock.
dn_opt_in_config() {
  local body='{}'
  [[ $# -lt 2 ]] || body="$2"
  mkdir -p "$1/.claude" && printf '%s\n' "$body" >"$1/.claude/agent-config.json"
}
dn_opt_in_lock() { mkdir -p "$1/.claude" && printf '{"kit": "agent-config-kit", "lockVersion": 1, "plugins": {}}\n' >"$1/.claude/agent-config-kit.lock"; }

# A PreToolUse payload: $1 tool name, $2 tool_input JSON, [$3 cwd].
dn_payload() {
  if [[ -n "${3:-}" ]]; then
    printf '{"session_id":"probe","hook_event_name":"PreToolUse","cwd":"%s","tool_name":"%s","tool_input":%s}' "$3" "$1" "$2"
  else
    printf '{"session_id":"probe","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":%s}' "$1" "$2"
  fi
}

# Runs the guard as the plugin runs it: $1 project, $2 payload, then VAR=value pairs for its env.
# DN_BASH picks the interpreter (default: bash on PATH; the 3.2 test passes /bin/bash).
dn_guard() {
  local proj="$1" payload="$2"
  shift 2
  printf '%s' "$payload" | env CLAUDE_PROJECT_DIR="$proj" CLAUDE_PLUGIN_ROOT="$DN_PLUGIN" \
    CLAUDE_PLUGIN_DATA="$BATS_TEST_TMPDIR/plugin-data" "$@" "${DN_BASH:-bash}" "$DN_GUARD"
}

# The same guard as a template copy runs it: no CLAUDE_PLUGIN_ROOT, so no project gate.
dn_guard_template_mode() {
  local proj="$1" payload="$2"
  printf '%s' "$payload" | env -u CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR="$proj" \
    AGENT_HOOK_STATE_DIR="$BATS_TEST_TMPDIR/hook-state" "${DN_BASH:-bash}" "$DN_GUARD"
}

# A PATH holding only what the guard needs besides a JSON reader: neither python3 nor jq.
dn_path_without_readers() {
  local bin="$BATS_TEST_TMPDIR/bin-no-readers" tool src
  mkdir -p "$bin"
  for tool in bash cat dirname git; do
    src="$(command -v "$tool")"
    ln -sf "$src" "$bin/$tool"
  done
  printf '%s' "$bin"
}

# A PATH of links to the tools the guard needs plus the ones named after $1 (a folder label), so a
# test chooses which JSON readers exist.
dn_path_with() {
  local bin="$BATS_TEST_TMPDIR/bin-$1" tool src
  shift
  mkdir -p "$bin"
  for tool in bash cat dirname git sleep "$@"; do
    src="$(command -v "$tool")" || return 1
    ln -sf "$src" "$bin/$tool"
  done
  printf '%s' "$bin"
}

# Puts a python3 that never answers into folder $1: a hung interpreter.
dn_hung_python() {
  printf '#!/bin/sh\nexec /bin/sleep 30\n' >"$1/python3"
  chmod +x "$1/python3"
}

# The timeout hooks.json gives the guard, in seconds.
dn_hook_timeout() {
  python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["hooks"]["PreToolUse"][0]["hooks"][0]["timeout"])' \
    "$DN_PLUGIN/hooks/hooks.json"
}

# The agent-core engine, when its unit has built it; tests that need it skip otherwise.
dn_engine() {
  [[ -x "$DN_CORE/bin/agent-setup" && -x "$DN_CORE/bin/agent-sync" ]]
}
