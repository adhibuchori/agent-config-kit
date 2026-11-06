#!/usr/bin/env bats
# scripts/check/audit.ts as the gate runs it, with `bun audit` stubbed: the script runs on the real
# Bun and spawns the stub found first on PATH. Each probe that must fail has one beside it that
# must pass.

load helpers

setup() {
  BUN="$(command -v bun)" || skip "bun is not installed"
  REPO="$BATS_TEST_TMPDIR/app"
  STUBS="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$REPO/scripts/check" "$REPO/node_modules/left-pad" "$STUBS"
  printf '{ "name": "left-pad", "version": "1.0.0" }\n' >"$REPO/node_modules/left-pad/package.json"
  cp "$STACK_DIR/scripts/check/audit.ts" "$REPO/scripts/check/"
}

# stub_audit <exit> [stdout]: what `bun audit --json` writes, and how it exits.
stub_audit() {
  printf '#!/usr/bin/env bash\nprintf %%s %q\necho "error: registry unreachable" >&2\nexit %s\n' "${2:-}" "$1" >"$STUBS/bun"
  chmod +x "$STUBS/bun"
}

audit() {
  # shellcheck disable=SC2016 # $1 to $3 expand in the child shell
  run --separate-stderr bash -c 'cd "$1" && PATH="$2:$PATH" "$3" scripts/check/audit.ts' _ "$REPO" "$STUBS" "$BUN"
}

@test "audit: a clean run with no output passes; no output with a failing exit is no report, not a pass" {
  stub_audit 0
  audit
  [ "$status" -eq 0 ]
  stub_audit 1
  audit
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"bun audit exited 1 without a report: error: registry unreachable"* ]] || false
}

@test "audit: a high advisory on an installed version fails; a moderate one and another range do not" {
  stub_audit 1 '{"left-pad":[{"url":"https://example.invalid/a","title":"t","severity":"high","vulnerable_versions":"<2.0.0"}]}'
  audit
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"left-pad@1.0.0"* ]] || false
  stub_audit 1 '{"left-pad":[{"url":"https://example.invalid/a","title":"t","severity":"moderate","vulnerable_versions":"<2.0.0"}]}'
  audit
  [ "$status" -eq 0 ]
  stub_audit 1 '{"left-pad":[{"url":"https://example.invalid/a","title":"t","severity":"high","vulnerable_versions":">=3.0.0"}]}'
  audit
  [ "$status" -eq 0 ]
}
