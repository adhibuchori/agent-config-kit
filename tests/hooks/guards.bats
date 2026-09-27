#!/usr/bin/env bats
# agent-core's guards (safety-check, db-guard, mcp-guard) and feedback hooks, run the way Claude
# Code runs them: JSON on stdin, a block is exit 2 with the reason on stderr. Covers the fail modes
# (a payload that is not one JSON object, no python3, no jq, neither) and the two MCP guards, whose
# plugin matchers (mcp__.* for db-guard) reach more tools than the template wiring did.

load ../helpers/common

setup() {
  kit_isolate "$BATS_TEST_TMPDIR/env"
  P="$BATS_TEST_TMPDIR/proj"
  new_repo "$P" feature/work
  printf '.claude/state/\n' >"$P/.gitignore"
  CP=(CLAUDE_PROJECT_DIR="$P")
}

# $1 target, $2 seconds until it ends (negative: already ended): an unlock file as unlock.sh writes it.
unlock_file() {
  mkdir -p "$P/.claude/state/unlock" && chmod 700 "$P/.claude/state" "$P/.claude/state/unlock"
  (umask 077 && printf '%s\n' "$(($(date +%s) + $2))" >"$P/.claude/state/unlock/$1")
}

@test "a guard refuses a payload that is not one JSON object, and says how to turn it off" {
  for bad in '{not json' '[]' '"text"' '' '{} {}' '{"tool_input": {"command": "git status"}'; do
    for h in safety-check.sh db-guard.sh mcp-guard.sh; do
      run -2 --separate-stderr hook "$h" "$bad" "${CP[@]}"
      [[ "$stderr" == *"To turn the guard off"* ]] || { echo "$h [$bad]: $stderr" >&2; return 1; }
    done
  done
}

@test "a feedback hook given a bad payload exits 0 and prints nothing" {
  for bad in '{not json' '[]' ''; do
    for h in post-edit.sh post-commit.sh prompt-intent.sh session-start.sh setup-check.sh; do
      run -0 --separate-stderr hook "$h" "$bad" "${CP[@]}"
      [ -z "$output" ] || { echo "$h [$bad] printed: $output" >&2; return 1; }
    done
  done
}

@test "a project folder that cannot be entered: guards refuse, feedback hooks stay quiet" {
  for h in safety-check.sh db-guard.sh mcp-guard.sh; do
    run -2 --separate-stderr hook "$h" "$(bash_payload "$P" "git status")" CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/absent"
  done
  run -0 --separate-stderr hook post-commit.sh "$(bash_payload "$P" "git status")" CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/absent"
  [ -z "$output" ]
}

@test "safety-check blocks a protected push and allows a read, with python3, without jq, and without python3" {
  for kit in full nojq nopy nojson; do
    env=("${CP[@]}")
    [ "$kit" = full ] || env+=(PATH="$(tool_kit "$kit" "$BATS_TEST_TMPDIR")")
    run -2 --separate-stderr hook safety-check.sh "$(bash_payload "$P" "git push origin dev")" "${env[@]}"
    [[ "$stderr" == *"BLOCKED: pushing to a protected branch"* ]] || { echo "$kit: $stderr" >&2; return 1; }
    run -2 --separate-stderr hook safety-check.sh "$(bash_payload "$P" "git reset --hard")" "${env[@]}"
  done
  run -0 --separate-stderr hook safety-check.sh "$(bash_payload "$P" "git status")" "${CP[@]}"
  run -0 --separate-stderr hook safety-check.sh "$(bash_payload "$P" "git status")" "${CP[@]}" PATH="$(tool_kit nojq "$BATS_TEST_TMPDIR")"
}

@test "mcp-guard blocks GitHub MCP writes to a protected branch, for any GitHub server name" {
  for tool in mcp__github__push_files mcp__github__create_or_update_file mcp__github__delete_file \
    mcp__github__create_branch mcp__plugin_github_github__push_files; do
    for branch in dev prod main master refs/heads/main; do
      run -2 --separate-stderr hook mcp-guard.sh "$(tool_payload "$tool" "{\"branch\": \"$branch\"}")" "${CP[@]}"
      [[ "$stderr" == *"[mcp-guard] BLOCKED"*"protected branch ${branch#refs/heads/}"* ]]
    done
    run -0 --separate-stderr hook mcp-guard.sh "$(tool_payload "$tool" '{"branch": "internal/feature"}')" "${CP[@]}"
  done
  run -0 --separate-stderr hook mcp-guard.sh "$(tool_payload mcp__github__push_files '{"files": []}')" "${CP[@]}"
}

@test "mcp-guard reads protectedBranches from .claude/agent-config.json" {
  mkdir -p "$P/.claude" && echo '{"protectedBranches": ["release"]}' >"$P/.claude/agent-config.json"
  run -2 --separate-stderr hook mcp-guard.sh "$(tool_payload mcp__github__push_files '{"branch": "release"}')" "${CP[@]}"
  run -0 --separate-stderr hook mcp-guard.sh "$(tool_payload mcp__github__push_files '{"branch": "main"}')" "${CP[@]}"
}

@test "mcp-guard works without jq or without python3, and refuses with neither" {
  for kit in nojq nopy; do
    run -2 --separate-stderr hook mcp-guard.sh "$(tool_payload mcp__github__push_files '{"branch": "dev"}')" "${CP[@]}" PATH="$(tool_kit "$kit" "$BATS_TEST_TMPDIR")"
    run -0 --separate-stderr hook mcp-guard.sh "$(tool_payload mcp__github__push_files '{"branch": "x"}')" "${CP[@]}" PATH="$(tool_kit "$kit" "$BATS_TEST_TMPDIR")"
  done
  run -2 --separate-stderr hook mcp-guard.sh "$(tool_payload mcp__github__push_files '{"branch": "x"}')" "${CP[@]}" PATH="$(tool_kit nojson "$BATS_TEST_TMPDIR")"
  [[ "$stderr" == *"To turn the guard off"* ]]
}

@test "db-guard lets one read-only statement through and blocks SQL that may write" {
  for q in "SELECT * FROM users WHERE id = 1" "WITH r AS (SELECT 1) SELECT * FROM r" "EXPLAIN SELECT 1" "SHOW search_path"; do
    run -0 --separate-stderr hook db-guard.sh "$(sql_payload mcp__db-prod__execute_sql "$q")" "${CP[@]}"
    [ -z "$output" ]
  done
  for q in "DELETE FROM users" "UPDATE t SET a = 1" "DROP TABLE t" "SELECT 1; DELETE FROM t" \
    "WITH gone AS (DELETE FROM s RETURNING *) SELECT count(*) FROM gone" "SELECT setval('s', 1)" "EXPLAIN ANALYZE DELETE FROM t"; do
    run -2 --separate-stderr hook db-guard.sh "$(sql_payload mcp__db-prod__execute_sql "$q")" "${CP[@]}"
    [[ "$stderr" == *"[db-guard] BLOCKED: this SQL may change the production database"*"./scripts/ops/unlock.sh db"* ]]
  done
}

@test "db-guard lets a write through while db is unlocked, and tells Claude; an expired or env unlock opens nothing" {
  unlock_file db 600
  run -0 --separate-stderr hook db-guard.sh "$(sql_payload mcp__db-prod__execute_sql "DELETE FROM sessions")" "${CP[@]}"
  [[ "$output" == *additionalContext*"The user has unlocked database writes until"* ]]
  rm -rf "$P/.claude/state" && unlock_file db -5
  run -2 --separate-stderr hook db-guard.sh "$(sql_payload mcp__db-prod__execute_sql "DELETE FROM sessions")" "${CP[@]}"
  rm -rf "$P/.claude/state" && unlock_file env 600
  run -2 --separate-stderr hook db-guard.sh "$(sql_payload mcp__db-prod__execute_sql "DELETE FROM sessions")" "${CP[@]}"
}

@test "wired on mcp__.* as a plugin, db-guard passes every tool outside its pattern silently" {
  for tool in mcp__serena__find_symbol mcp__github__get_file_contents mcp__db-dev__execute_sql mcp__context7__query-docs; do
    run -0 --separate-stderr hook db-guard.sh "$(sql_payload "$tool" "DELETE FROM users")" "${CP[@]}"
    [ -z "$output" ] && [ -z "$stderr" ]
  done
}

@test "db-guard judges the tool dbWriteGuard.toolPattern names, and a malformed pattern keeps the default" {
  mkdir -p "$P/.claude"
  echo '{"dbWriteGuard": {"toolPattern": "mcp__pg__(query|execute)"}}' >"$P/.claude/agent-config.json"
  run -2 --separate-stderr hook db-guard.sh "$(sql_payload mcp__pg__query "DELETE FROM t")" "${CP[@]}"
  run -0 --separate-stderr hook db-guard.sh "$(sql_payload mcp__pg__query "SELECT 1")" "${CP[@]}"
  run -0 --separate-stderr hook db-guard.sh "$(sql_payload mcp__db-prod__execute_sql "DELETE FROM t")" "${CP[@]}"
  echo '{"dbWriteGuard": {"toolPattern": "("}}' >"$P/.claude/agent-config.json"
  run -2 --separate-stderr hook db-guard.sh "$(sql_payload mcp__db-prod__execute_sql "DELETE FROM t")" "${CP[@]}"
}

@test "db-guard needs python3: without it every call is refused, reads included; without jq it works" {
  run -2 --separate-stderr hook db-guard.sh "$(sql_payload mcp__db-prod__execute_sql "SELECT 1")" "${CP[@]}" PATH="$(tool_kit nopy "$BATS_TEST_TMPDIR")"
  [[ "$stderr" == *"db-guard reads SQL with python3"*"To turn the guard off"* ]]
  run -0 --separate-stderr hook db-guard.sh "$(sql_payload mcp__db-prod__execute_sql "SELECT 1")" "${CP[@]}" PATH="$(tool_kit nojq "$BATS_TEST_TMPDIR")"
  run -2 --separate-stderr hook db-guard.sh "$(sql_payload mcp__db-prod__execute_sql "DELETE FROM t")" "${CP[@]}" PATH="$(tool_kit nojq "$BATS_TEST_TMPDIR")"
}

@test "a guard's JSON on stdout is empty on a pass: only a warning carries hookSpecificOutput" {
  run -0 --separate-stderr hook safety-check.sh "$(bash_payload "$P" "ls")" "${CP[@]}"
  [ -z "$output" ]
  run -0 --separate-stderr hook mcp-guard.sh "$(tool_payload mcp__github__push_files '{"branch": "x"}')" "${CP[@]}"
  [ -z "$output" ]
}
