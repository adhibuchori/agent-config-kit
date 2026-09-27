#!/usr/bin/env bats
# generated-guard.sh as agent-fe-nextjs ships it: the plugin-mode project gate, what it blocks and
# lets through, and its fail-closed behaviour when a payload or a JSON reader is missing.

load helpers

setup() {
  P="$BATS_TEST_TMPDIR/app"
  make_project "$P"
  EDIT_GEN="$(tool_json Edit "{\"file_path\": \"$P/src/lib/api/generated/api.ts\"}")"
  EDIT_OK="$(tool_json Edit "{\"file_path\": \"$P/src/lib/api/client/mutator.ts\"}")"
}

@test "plugin mode, no opt-in: silent exit 0 even for a generated file" {
  run --separate-stderr guard_plugin "$P" "$EDIT_GEN"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "plugin mode, no opt-in: a malformed payload is not read either" {
  run --separate-stderr guard_plugin "$P" '{not json'
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

@test "plugin mode, opted in by the lock: Edit of generated output is blocked" {
  opt_in_lock "$P"
  run -2 --separate-stderr guard_plugin "$P" "$EDIT_GEN"
  [[ "$stderr" == *"[generated-guard] BLOCKED: src/lib/api/generated/api.ts is generated output"* ]] || false
}

@test "plugin mode, opted in by .claude/agent-config.json: Edit of generated output is blocked" {
  opt_in_config "$P"
  run -2 --separate-stderr guard_plugin "$P" "$EDIT_GEN"
  [[ "$stderr" == *"generated output"* ]] || false
}

@test "template mode (no CLAUDE_PLUGIN_ROOT): the guard runs without an opt-in" {
  run -2 --separate-stderr guard_template "$P" "$EDIT_GEN"
  [[ "$stderr" == *"BLOCKED"* ]] || false
}

@test "opted in: a hand-written file beside the generated client is allowed" {
  opt_in_lock "$P"
  run -0 --separate-stderr guard_plugin "$P" "$EDIT_OK"
  [ -z "$stderr" ]
}

@test "opted in: Write by relative path into the generated folder is blocked" {
  opt_in_lock "$P"
  run -2 --separate-stderr guard_plugin "$P" "$(tool_json Write '{"file_path": "src/lib/api/generated/new.ts"}')"
}

@test "opted in: the copied OpenAPI contract is blocked with its own reason" {
  opt_in_lock "$P"
  run -2 --separate-stderr guard_plugin "$P" "$(tool_json Edit "{\"file_path\": \"$P/openapi.json\"}")"
  [[ "$stderr" == *"is the API contract"* ]] || false
}

@test "opted in: Serena's replace_content on a generated file is blocked" {
  opt_in_lock "$P"
  run -2 --separate-stderr guard_plugin "$P" \
    "$(tool_json mcp__serena__replace_content '{"relative_path": "src/lib/api/generated/api.ts"}')"
}

@test "opted in: a folder-wide replace_in_files that reaches generated output is blocked" {
  opt_in_lock "$P"
  run -2 --separate-stderr guard_plugin "$P" \
    "$(tool_json mcp__serena__replace_in_files '{"relative_path": "src/lib/api", "needle": "probeNeedle", "repl": "x", "mode": "literal"}')"
  [[ "$stderr" == *"replace_in_files reaches generated output"* ]] || false
}

@test "opted in: a replace_in_files whose needle is absent from generated output is allowed" {
  opt_in_lock "$P"
  run -0 guard_plugin "$P" \
    "$(tool_json mcp__serena__replace_in_files '{"relative_path": "src/lib/api", "needle": "absentNeedle", "repl": "x", "mode": "literal"}')"
}

@test "generatedPaths in .claude/agent-config.json replaces the default list whole" {
  opt_in_config "$P" '{"generatedPaths": ["content/generated"]}'
  run -2 guard_plugin "$P" "$(tool_json Write "{\"file_path\": \"$P/content/generated/page.mdx\"}")"
  run -0 guard_plugin "$P" "$EDIT_GEN"
}

@test "opted in: a payload that is not one JSON object is refused, with how to turn the guard off" {
  opt_in_lock "$P"
  for bad in '{not json' '[]' '"text"' '{} {}'; do
    run -2 --separate-stderr guard_plugin "$P" "$bad"
    [[ "$stderr" == *"To turn the guard off"* ]] || false
  done
}

@test "no jq: python3 reads the call and the guard still blocks and allows" {
  opt_in_lock "$P"
  make_kits
  run -2 guard_plugin "$P" "$EDIT_GEN" PATH="$BATS_TEST_TMPDIR/nojq"
  run -0 guard_plugin "$P" "$EDIT_OK" PATH="$BATS_TEST_TMPDIR/nojq"
}

@test "no python3: jq reads the call; a replace_in_files it cannot size is refused" {
  opt_in_lock "$P"
  make_kits
  run -2 guard_plugin "$P" "$EDIT_GEN" PATH="$BATS_TEST_TMPDIR/nopy"
  run -0 guard_plugin "$P" "$EDIT_OK" PATH="$BATS_TEST_TMPDIR/nopy"
  run -2 --separate-stderr guard_plugin "$P" \
    "$(tool_json mcp__serena__replace_in_files '{"relative_path": "src/lib/api", "needle": "absentNeedle", "repl": "x", "mode": "literal"}')" \
    PATH="$BATS_TEST_TMPDIR/nopy"
  [[ "$stderr" == *"To turn the guard off"* ]] || false
}

@test "neither python3 nor jq: every guarded call is refused (fail closed)" {
  opt_in_lock "$P"
  make_kits
  run -2 --separate-stderr guard_plugin "$P" "$EDIT_OK" PATH="$BATS_TEST_TMPDIR/nojson"
  [[ "$stderr" == *"neither python3 nor jq"* ]] || false
}

@test "the guard writes nothing under the plugin root" {
  opt_in_lock "$P"
  before="$(find "$PLUGIN" -newer "$GUARD" -type f | sort)"
  run -2 guard_plugin "$P" "$EDIT_GEN"
  after="$(find "$PLUGIN" -newer "$GUARD" -type f | sort)"
  [ "$before" = "$after" ]
}
