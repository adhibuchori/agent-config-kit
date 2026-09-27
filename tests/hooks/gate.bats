#!/usr/bin/env bats
# The plugin-mode project gate (lib.sh hook_gate). Run by Claude Code as a plugin, CLAUDE_PLUGIN_ROOT
# is set, and every agent-core hook stays silent in a project that has neither
# .claude/agent-config.json nor .claude/agent-config-kit.lock. Either file turns every hook on.
# Copied into a repo as a template (no CLAUDE_PLUGIN_ROOT), the hooks always run.

load ../helpers/common

setup() {
  kit_isolate "$BATS_TEST_TMPDIR/env"
  P="$BATS_TEST_TMPDIR/proj"
  new_repo "$P" feature/work
  printf '{"a": }\n' >"$P/bad.json"
  mkdir -p "$P/.claude/commands" && echo '# rca' >"$P/.claude/commands/rca.md"
  PLUGIN=(CLAUDE_PLUGIN_ROOT="$CORE" CLAUDE_PROJECT_DIR="$P")
  PUSH="$(bash_payload "$P" "git push --force origin main")"
  SQL="$(sql_payload mcp__db-prod__execute_sql "DELETE FROM users")"
  MCP="$(tool_payload mcp__github__push_files '{"branch": "main"}')"
  EDIT="$(tool_payload Edit "{\"file_path\": \"$P/bad.json\"}")"
  PROMPT='{"session_id": "s", "hook_event_name": "UserPromptSubmit", "prompt": "/debug the login"}'
}

# $1 expected exit, then VAR=value pairs: every guard against a call it refuses.
guards_exit() {
  local want="$1"
  shift
  run "-$want" --separate-stderr hook safety-check.sh "$PUSH" "$@"
  run "-$want" --separate-stderr hook db-guard.sh "$SQL" "$@"
  run "-$want" --separate-stderr hook mcp-guard.sh "$MCP" "$@"
  run "-$want" --separate-stderr hook safety-check.sh '{not json' "$@"
}

@test "a project that has not opted in gets no hook at all: exit 0, nothing on stdout or stderr" {
  for pair in "safety-check.sh:$PUSH" "db-guard.sh:$SQL" "mcp-guard.sh:$MCP" "safety-check.sh:{not json" \
    "post-edit.sh:$EDIT" "prompt-intent.sh:$PROMPT" "setup-check.sh:{}" "post-commit.sh:$PUSH"; do
    run -0 --separate-stderr hook "${pair%%:*}" "${pair#*:}" "${PLUGIN[@]}"
    [ -z "$output" ] && [ -z "$stderr" ] || {
      printf '%s spoke without opt-in:\n%s\n%s\n' "${pair%%:*}" "$output" "$stderr" >&2
      return 1
    }
  done
  run -0 --separate-stderr hook session-start.sh '{}' "${PLUGIN[@]}" CLAUDE_ENV_FILE="$BATS_TEST_TMPDIR/envfile"
  [ ! -e "$BATS_TEST_TMPDIR/envfile" ]
}

@test "opting in with the lock turns every guard on" {
  touch "$P/.claude/agent-config-kit.lock"
  guards_exit 2 "${PLUGIN[@]}"
  run -0 --separate-stderr hook post-edit.sh "$EDIT" "${PLUGIN[@]}"
  [[ "$output" == *additionalContext* ]]
}

@test "opting in with .claude/agent-config.json turns every guard on" {
  echo '{}' >"$P/.claude/agent-config.json"
  guards_exit 2 "${PLUGIN[@]}"
  run -0 --separate-stderr hook session-start.sh '{}' "${PLUGIN[@]}" CLAUDE_ENV_FILE="$BATS_TEST_TMPDIR/envfile"
  [ -s "$BATS_TEST_TMPDIR/envfile" ]
}

@test "copied as a template (no CLAUDE_PLUGIN_ROOT), the hooks run without either file" {
  guards_exit 2 CLAUDE_PROJECT_DIR="$P"
}

@test "without CLAUDE_PROJECT_DIR the gate finds the project from the git top level" {
  touch "$P/.claude/agent-config-kit.lock"
  mkdir -p "$P/deep/er"
  cd "$P/deep/er"
  run -2 --separate-stderr hook safety-check.sh "$(bash_payload "$P/deep/er" "git push --force origin main")" CLAUDE_PLUGIN_ROOT="$CORE"
  rm "$P/.claude/agent-config-kit.lock"
  run -0 --separate-stderr hook safety-check.sh "$(bash_payload "$P/deep/er" "git push --force origin main")" CLAUDE_PLUGIN_ROOT="$CORE"
}

@test "an opted-in plugin keeps its per-session state in CLAUDE_PLUGIN_DATA and writes nothing under the plugin" {
  touch "$P/.claude/agent-config-kit.lock"
  before="$(tree_state "$CORE")"
  run -0 --separate-stderr hook safety-check.sh "$(bash_payload "$P" "git commit -m x" toolu_2)" "${PLUGIN[@]}" \
    CLAUDE_PLUGIN_DATA="$BATS_TEST_TMPDIR/data" AGENT_HOOK_STATE_DIR=
  [ -n "$(find "$BATS_TEST_TMPDIR/data/hook-state/probe-session/heads" -type f)" ]
  [ "$(tree_state "$CORE")" = "$before" ]
}

@test "opted in as a plugin, safety-check gives the probe table's verdict (every 12th row)" {
  probe_fixture "$BATS_FILE_TMPDIR"
  probe_branch "$BATS_FILE_TMPDIR" dev >/dev/null
  probe_branch "$BATS_FILE_TMPDIR" main >/dev/null
  FIX_TMP="$BATS_FILE_TMPDIR" FIX_PROJ="$BATS_FILE_TMPDIR/proj"
  mkdir -p "$FIX_PROJ/.claude" && touch "$FIX_PROJ/.claude/agent-config-kit.lock"
  local n=0 checked=0 bad=0 expect spec cmd cwd got
  while IFS=$'\t' read -r expect spec cmd || [ -n "${expect:-}" ]; do
    n=$((n + 1))
    case "$expect" in '' | '#'*) continue ;; esac
    [ $((n % 12)) -eq 0 ] || continue
    cmd="${cmd//@TMP@/$FIX_TMP}" cwd="$FIX_PROJ"
    [ "$spec" = - ] || cwd="$FIX_TMP/on-${spec//\//-}"
    run --separate-stderr hook safety-check.sh "$(bash_payload "$cwd" "$cmd")" CLAUDE_PLUGIN_ROOT="$CORE" CLAUDE_PROJECT_DIR="$FIX_PROJ"
    got=allow
    [ "$status" -eq 2 ] && got=block
    [ "$status" -eq 0 ] && [[ "$output" == *additionalContext* ]] && got=warn
    checked=$((checked + 1))
    if [ "$got" != "$expect" ]; then
      bad=$((bad + 1))
      printf 'L%d expected %s, got %s (exit %s): %s\n' "$n" "$expect" "$got" "$status" "$cmd" >&2
    fi
  done <"$COMMON/scripts/check/hook-probes.tsv"
  [ "$checked" -ge 40 ] && [ "$bad" -eq 0 ]
}
