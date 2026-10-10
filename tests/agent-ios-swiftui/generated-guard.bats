#!/usr/bin/env bats
# generated-guard.sh as agent-ios-swiftui ships it, with the generatedPaths setup seeds: the generated
# client, the payload registry and the spec copy are refused, the hand-written files beside them are
# not, and nothing is refused until the project opts in.

load helpers

setup() {
  ios_setup_env
  P="$BATS_TEST_TMPDIR/app"
  git init -q "$P"
  git -C "$P" commit -q --allow-empty -m init
  mkdir -p "$P/Packages/AppCore/Sources/APIClient/GeneratedSources"
  echo 'struct Client {}' >"$P/Packages/AppCore/Sources/APIClient/GeneratedSources/Client.swift"
  echo '{"openapi": "3.1.0"}' >"$P/Packages/AppCore/Sources/APIClient/openapi.json"
  cp "$TPL/Packages/AppCore/Sources/APIClient/AppProblem.swift" "$P/Packages/AppCore/Sources/APIClient/"
  GEN="$(tool_json Edit "{\"file_path\": \"$P/Packages/AppCore/Sources/APIClient/GeneratedSources/Client.swift\"}")"
  SPEC="$(tool_json Write "{\"file_path\": \"$P/Packages/AppCore/Sources/APIClient/openapi.json\"}")"
  OWN="$(tool_json Edit "{\"file_path\": \"$P/Packages/AppCore/Sources/APIClient/AppProblem.swift\"}")"
}

opt_in() { mkdir -p "$P/.claude" && cp "$TPL/.claude/agent-config.json" "$P/.claude/agent-config.json"; }

@test "no opt-in: silent exit 0, even for the generated client" {
  run --separate-stderr guard_plugin "$P" "$GEN"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

@test "opted in with the seeded config: an edit of the generated client is blocked" {
  opt_in
  run -2 --separate-stderr guard_plugin "$P" "$GEN"
  [[ "$stderr" == *"[generated-guard] BLOCKED: Packages/AppCore/Sources/APIClient/GeneratedSources/Client.swift is generated output"* ]] || false
}

@test "opted in: a write to the spec copy is blocked as the API contract" {
  opt_in
  run -2 --separate-stderr guard_plugin "$P" "$SPEC"
  [[ "$stderr" == *"is the API contract, exported by this service or copied from the one that owns it"* ]] || false
}

@test "opted in: the hand-written AppProblem beside the client is allowed" {
  opt_in
  run -0 --separate-stderr guard_plugin "$P" "$OWN"
  [ -z "$stderr" ]
}

@test "opted in: a folder-wide replace_in_files that reaches the client is blocked" {
  opt_in
  run -2 --separate-stderr guard_plugin "$P" \
    "$(tool_json mcp__serena__replace_in_files '{"relative_path": "Packages/AppCore", "needle": "struct Client", "repl": "x", "mode": "literal"}')"
  [[ "$stderr" == *"replace_in_files reaches generated output"* ]] || false
}

@test "opted in: the generated payload registry is blocked, the hand-written payload files beside it are not" {
  opt_in
  local api="$P/Packages/AppCore/Sources/APIClient"
  echo 'enum PayloadEndpoints {}' >"$api/PayloadEndpoints.generated.swift"
  cp "$TPL/Packages/AppCore/Sources/APIClient/PayloadMiddleware.swift" "$api/"
  run -2 --separate-stderr guard_plugin "$P" "$(tool_json Edit "{\"file_path\": \"$api/PayloadEndpoints.generated.swift\"}")"
  [[ "$stderr" == *"PayloadEndpoints.generated.swift is generated output"* ]] || false
  run -0 --separate-stderr guard_plugin "$P" "$(tool_json Edit "{\"file_path\": \"$api/PayloadMiddleware.swift\"}")"
  [ -z "$stderr" ]
}

@test "the seeded generatedPaths name the client folder, the payload registry and the spec copy" {
  run jq -r '.generatedPaths | join(",")' "$TPL/.claude/agent-config.json"
  [ "$output" = "Packages/AppCore/Sources/APIClient/GeneratedSources,Packages/AppCore/Sources/APIClient/PayloadEndpoints.generated.swift,Packages/AppCore/Sources/APIClient/openapi.json,Packages/AppCore/Sources/APIClient/openapi.yaml" ]
}
