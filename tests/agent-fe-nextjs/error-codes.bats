#!/usr/bin/env bats
# check:error-codes, proven both ways on a toy app: every code the spec publishes has a row, and the
# problem-type base the app resolves types by is the one the API mints them under. Runs on Bun, or
# on Node with tests/helpers/ts-resolve.mjs where Bun is absent.

load helpers

BASE='https://example.invalid/problems/'

setup() {
  if command -v bun >/dev/null 2>&1; then
    TS=(bun)
  elif node -e 'process.exit(process.features.typescript ? 0 : 1)' 2>/dev/null; then
    TS=(node --no-warnings --import "$KIT_ROOT/tests/helpers/ts-resolve.mjs")
  else
    skip "neither bun nor a node that strips TypeScript types is installed"
  fi
  REPO="$BATS_TEST_TMPDIR/app"
  mkdir -p "$REPO/scripts/check" "$REPO/src/lib/errors"
  printf '{ "name": "toy", "private": true, "type": "module" }\n' >"$REPO/package.json"
  cp "$STACK_DIR/scripts/check/error-codes.ts" "$REPO/scripts/check/"
}

# spec [base]: an openapi.json whose Problem publishes two codes, and the base when one is given.
spec() {
  python3 - "$REPO/openapi.json" "${1-}" <<'PY'
import json, sys
path, base = sys.argv[1], sys.argv[2]
kind = {"type": "string", "format": "uri"}
if base:
    kind["x-problem-type-base"] = base
problem = {"type": "object", "properties": {"type": kind, "code": {"type": "string", "enum": ["NOT_FOUND", "ENVELOPE_REQUIRED"]}}}
json.dump({"openapi": "3.1.0", "components": {"schemas": {"Problem": problem}}}, open(path, "w"))
PY
}

# keys [base]: a problem-key.ts that maps both codes, and exports the base when one is given.
keys() {
  {
    printf "export const CODE_TO_KEY = { NOT_FOUND: 'errors.notFound', ENVELOPE_REQUIRED: 'errors.sealed' };\n"
    [ -z "${1-}" ] || printf "export const PROBLEM_TYPE_BASE = '%s';\n" "$1"
  } >"$REPO/src/lib/errors/problem-key.ts"
}

check() { run --separate-stderr bash -c 'cd "$1" && shift && "$@" scripts/check/error-codes.ts' _ "$REPO" "${TS[@]}"; }

@test "error-codes: the app's base equals the one the spec publishes, so it passes" {
  spec "$BASE"
  keys "$BASE"
  check
  [ "$status" -eq 0 ]
  [[ "$output" == *"All 2 API error codes have a message or a stated reason"* ]]
  [[ "$output" != *"problems resolve by code"* ]]
}

@test "error-codes: a base that differs from the spec's fails, naming both" {
  spec "$BASE"
  keys 'https://api.example.com/problems/'
  check
  [ "$status" -eq 1 ]
  [[ "$stderr" == *'PROBLEM_TYPE_BASE is "https://api.example.com/problems/", but openapi.json publishes https://example.invalid/problems/'* ]]
}

@test "error-codes: a spec that publishes a base fails where the app exports none" {
  spec "$BASE"
  keys
  check
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"problem-key.ts exports no PROBLEM_TYPE_BASE; the API mints types under $BASE"* ]]
}

@test "error-codes: a spec with no base and an app with no export pass, and say problems resolve by code" {
  spec
  keys
  check
  [ "$status" -eq 0 ]
  [[ "$output" == *"openapi.json publishes no problem-type base; problems resolve by code"* ]]
}

@test "error-codes: an app that exports a base the spec does not publish fails" {
  spec
  keys "$BASE"
  check
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"PROBLEM_TYPE_BASE is exported, but openapi.json publishes no x-problem-type-base"* ]]
}

@test "error-codes: a malformed base in the spec fails, even where the app copied it" {
  spec 'https://example.invalid/problems'
  keys 'https://example.invalid/problems'
  check
  [ "$status" -eq 1 ]
  [[ "$stderr" == *'openapi.json: x-problem-type-base "https://example.invalid/problems" does not end in /'* ]]
}

@test "error-codes: a code with no row fails; mapping it passes" {
  spec "$BASE"
  printf "export const PROBLEM_TYPE_BASE = '%s';\nexport const CODE_TO_KEY = { NOT_FOUND: 'errors.notFound' };\n" "$BASE" \
    >"$REPO/src/lib/errors/problem-key.ts"
  check
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"ENVELOPE_REQUIRED: no row in src/lib/errors/problem-key.ts and no exemption here"* ]]
  keys "$BASE"
  check
  [ "$status" -eq 0 ]
}
