#!/usr/bin/env bats
# agent-core's feedback hooks, which add context and never block: setup-check (plugin only), the
# plugin-mode /debug pointer in prompt-intent, and session-start.

load ../helpers/common

setup() {
  kit_isolate "$BATS_TEST_TMPDIR/env"
  P="$BATS_TEST_TMPDIR/proj"
  new_repo "$P"
  mkdir -p "$P/.claude"
  PLUGIN=(CLAUDE_PLUGIN_ROOT="$CORE" CLAUDE_PROJECT_DIR="$P")
  VERSION="$(json_q "$CORE/.claude-plugin/plugin.json" 'd["version"]')"
}

# $1 agent-core version to record: a lock as setup writes it, reduced to what setup-check reads.
lock_with() {
  printf '{"kit": "agent-config-kit", "lockVersion": 1, "plugins": {"agent-core": {"version": "%s"}}}\n' "$1" \
    >"$P/.claude/agent-config-kit.lock"
}

@test "setup-check: opted in without a lock, it points at setup" {
  echo '{}' >"$P/.claude/agent-config.json"
  run -0 --separate-stderr hook setup-check.sh '{}' "${PLUGIN[@]}"
  [[ "$output" == *'"hookEventName":"SessionStart"'* || "$output" == *'"hookEventName": "SessionStart"'* ]]
  [[ "$output" == *"setup has not run here"*"/agent-core:setup"* ]]
}

@test "setup-check: a lock from another agent-core version points at sync" {
  lock_with 0.9.0
  run -0 --separate-stderr hook setup-check.sh '{}' "${PLUGIN[@]}"
  [[ "$output" == *"set up with agent-core 0.9.0, and $VERSION is installed"*"/agent-core:sync"* ]]
}

@test "setup-check: a lock without an agent-core entry points at setup" {
  printf '{"plugins": {"agent-x": {"version": "1.0.0"}}}\n' >"$P/.claude/agent-config-kit.lock"
  run -0 --separate-stderr hook setup-check.sh '{}' "${PLUGIN[@]}"
  [[ "$output" == *"has no agent-core entry"*"/agent-core:setup"* ]]
}

@test "setup-check: a lock at this version, a project not opted in, or an unreadable lock says nothing" {
  lock_with "$VERSION"
  run -0 --separate-stderr hook setup-check.sh '{}' "${PLUGIN[@]}"
  [ -z "$output" ]
  echo 'not json' >"$P/.claude/agent-config-kit.lock"
  run -0 --separate-stderr hook setup-check.sh '{}' "${PLUGIN[@]}"
  rm "$P/.claude/agent-config-kit.lock"
  run -0 --separate-stderr hook setup-check.sh '{}' "${PLUGIN[@]}"
  [ -z "$output" ] && [ -z "$stderr" ]
}

@test "setup-check works with python3 alone, and is silent with neither jq nor python3" {
  lock_with 0.9.0
  run -0 --separate-stderr hook setup-check.sh '{}' "${PLUGIN[@]}" PATH="$(tool_kit nojq "$BATS_TEST_TMPDIR")"
  [[ "$output" == *"/agent-core:sync"* ]]
  run -0 --separate-stderr hook setup-check.sh '{}' "${PLUGIN[@]}" PATH="$(tool_kit nojson "$BATS_TEST_TMPDIR")"
  [ -z "$output" ]
}

@test "setup-check never writes: the project and the plugin are unchanged" {
  echo '{}' >"$P/.claude/agent-config.json"
  before="$(tree_state "$P")$(tree_state "$CORE")"
  run -0 --separate-stderr hook setup-check.sh '{}' "${PLUGIN[@]}"
  [ "$(tree_state "$P")$(tree_state "$CORE")" = "$before" ]
}

@test "prompt-intent: as a plugin, /debug points at /agent-core:rca when the project has no /rca of its own" {
  touch "$P/.claude/agent-config-kit.lock"
  run -0 --separate-stderr hook prompt-intent.sh '{"session_id": "s", "hook_event_name": "UserPromptSubmit", "prompt": "/debug the login"}' "${PLUGIN[@]}"
  [[ "$output" == *"the /agent-core:rca command"*"skill \`agent-core:rca\`"* ]]
  mkdir -p "$P/.claude/commands" && echo '# rca' >"$P/.claude/commands/rca.md"
  run -0 --separate-stderr hook prompt-intent.sh '{"session_id": "s", "hook_event_name": "UserPromptSubmit", "prompt": "/debug the login"}' "${PLUGIN[@]}"
  [[ "$output" == *"this project's /rca command"*"skill \`rca\`"* ]]
}

@test "prompt-intent: copied as a template without an /rca command, /debug adds nothing" {
  run -0 --separate-stderr hook prompt-intent.sh '{"session_id": "s", "hook_event_name": "UserPromptSubmit", "prompt": "/debug"}' CLAUDE_PROJECT_DIR="$P"
  [[ "$output" != *"rca"* ]]
}

@test "session-start writes the zsh options line once into CLAUDE_ENV_FILE, however often it runs" {
  touch "$P/.claude/agent-config-kit.lock"
  for _ in 1 2 3; do
    run -0 --separate-stderr hook session-start.sh '{}' "${PLUGIN[@]}" CLAUDE_ENV_FILE="$BATS_TEST_TMPDIR/envfile"
  done
  [ "$(grep -c 'setopt NO_NOMATCH NO_EQUALS SH_WORD_SPLIT' "$BATS_TEST_TMPDIR/envfile")" -eq 1 ]
}
