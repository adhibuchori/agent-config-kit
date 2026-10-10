#!/usr/bin/env bats
# The Go payload core (templates/be-go/internal/payload) against the shared vectors, in a module of
# its own: standard library only, so no download. Its tests pass at 100% of statements, and two
# drifts fail them: a lower-cased request AAD, and a changed HKDF label. Needs Go 1.26 or newer
# (crypto/hkdf, errors.AsType); every test skips, saying so, without it.

load helpers

setup() {
  go_setup_env
  command -v go >/dev/null 2>&1 || skip "go is not installed; the payload core's tests need Go 1.26 or newer"
  local version minor
  version="$(go env GOVERSION 2>/dev/null)"
  minor="$(printf '%s' "$version" | sed -nE 's/^go1\.([0-9]+).*/\1/p')"
  { [ -n "$minor" ] && [ "$minor" -ge 26 ]; } || skip "go is ${version:-unreadable}; the payload core needs Go 1.26 or newer"
  MOD="$BATS_TEST_TMPDIR/mod"
  mkdir -p "$MOD/internal" "$MOD/scripts/check"
  cp -R "$TPL/internal/payload" "$MOD/internal/"
  cp "$TPL/scripts/check/payload-vectors.json" "$MOD/scripts/check/"
  printf 'module example.com/service\n\ngo 1.26\n' >"$MOD/go.mod"
  export GOTOOLCHAIN=local GOFLAGS=-mod=mod GOPROXY=off
}

# go_test [flags...]: the core's tests, never from the cache.
go_test() {
  (cd "$MOD" && go test -count=1 "$@" ./internal/payload/)
}

# drift <file> <from> <to>: the core with one literal changed, as a careless edit would change it.
drift() {
  local f="$MOD/internal/payload/$1"
  grep -qF "$2" "$f"
  sed "s#$2#$3#" "$f" >"$f.new" && mv "$f.new" "$f"
  run grep -qF "$3" "$f"
  [ "$status" -eq 0 ]
}

@test "the payload core passes its tests, the shared vectors included, at 100% of statements" {
  run go_test -coverprofile="$MOD/cover.out"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"coverage: 100.0% of statements"* ]] || false
  run go_test -run 'TestVectors' -v
  [[ "$output" == *"--- PASS: TestVectorsOpenAndRejects"* ]] || false
  [[ "$output" == *"--- PASS: TestVectorsAgreeFromBothSides"* ]] || false
  [[ "$output" == *"--- PASS: TestVectorsPointRejects"* ]] || false
}

@test "a lower-cased request AAD fails the vectors" {
  drift envelope.go 'strings.ToUpper(method)' 'strings.ToLower(method)'
  run go_test -run 'TestVectors'
  echo "$output"
  [ "$status" -ne 0 ]
  [[ "$output" == *'AAD "1.post./api/notes.k1.1767225600000", the vectors say "1.POST./api/notes.k1.1767225600000"'* ]] || false
}

@test "a changed HKDF label fails the key agreement" {
  drift ecdh.go '"payload-envelope/v1/browser"' '"payload-envelope/v1/app"'
  run go_test -run 'TestVectorsAgreeFromBothSides'
  echo "$output"
  [ "$status" -ne 0 ]
  [[ "$output" == *'HKDF info "payload-envelope/v1/app", the vectors say "payload-envelope/v1/browser"'* ]] || false
  # The derived key differs too, so the label is caught even without the line that compares it.
  [[ "$output" == *", the vectors say "*" (<nil>)"* ]] || false
}
