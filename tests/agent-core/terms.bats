#!/usr/bin/env bats
# scripts/check/terms.mjs, run from a project the way gates.sh runs it. Each probe that must fail
# has one beside it that must pass.

load ../helpers/common

setup() {
  kit_isolate "$BATS_TEST_TMPDIR/env"
  command -v node >/dev/null || skip "node is not installed"
  P="$BATS_TEST_TMPDIR/proj"
  new_repo "$P"
  mkdir -p "$P/scripts/check" "$P/src"
  cp "$COMMON/scripts/check/terms.mjs" "$P/scripts/check/terms.mjs"
}

terms() { run --separate-stderr node "$P/scripts/check/terms.mjs"; }

# $1 the allow array, as JSON. The vocabulary holds one word, with its reason.
config() {
  printf '{"roots": ["src"], "exclude": ["src/vendor/"], "forbidden": [{"term": "guaranteed?", "why": "we promise no outcome"}], "allow": %s}\n' "${1:-[]}" \
    >"$P/scripts/check/terms.config.json"
}

stage() { git -C "$P" add -A; }

@test "terms: the shipped config lists nothing, so the check says so and passes" {
  cp "$COMMON/scripts/check/terms.config.json" "$P/scripts/check/"
  terms
  [ "$status" -eq 0 ]
  [[ "$output" == *"no forbidden term listed"* ]] || false
}

@test "terms: without a config file the check says so and passes" {
  terms
  [ "$status" -eq 0 ]
  [[ "$output" == *"no forbidden term listed"* ]] || false
}

@test "terms: a listed word fails, named by file, line and reason; a clean file passes" {
  config
  printf 'one\nresults guaranteed\n' >"$P/src/a.md"
  stage
  terms
  [ "$status" -eq 1 ]
  [[ "$stderr" == *'src/a.md:2  "guaranteed": we promise no outcome'* ]] || false
  printf 'one\nresults vary\n' >"$P/src/a.md"
  stage
  terms
  [ "$status" -eq 0 ]
  [[ "$output" == *"scanned 1 files"* ]] || false
}

@test "terms: an allow phrase clears itself only, in its own file" {
  config '[{"path": "src/a.md", "phrase": "not guaranteed", "reason": "a disclaimer"}]'
  printf 'not guaranteed\n' >"$P/src/a.md"
  stage
  terms
  [ "$status" -eq 0 ]
  printf 'not guaranteed, but guaranteed\n' >"$P/src/a.md"
  stage
  terms
  [ "$status" -eq 1 ]
  printf 'not guaranteed\n' >"$P/src/a.md"
  printf 'not guaranteed\n' >"$P/src/b.md"
  stage
  terms
  [ "$status" -eq 1 ]
  [[ "$stderr" == *'src/b.md:1'* ]] || false
}

@test "terms: an allow entry whose phrase left its file fails as stale" {
  config '[{"path": "src/a.md", "phrase": "not guaranteed", "reason": "a disclaimer"}]'
  printf 'plain\n' >"$P/src/a.md"
  stage
  terms
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"stale allow entry"* ]] || false
}

@test "terms: an allow entry without its reason is refused" {
  config '[{"path": "src/a.md", "phrase": "not guaranteed"}]'
  printf 'plain\n' >"$P/src/a.md"
  stage
  terms
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"allow {path, phrase, reason}"* ]] || false
}

@test "terms: a vocabulary that scanned no file fails: the roots are wrong, nothing was checked" {
  config
  terms
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"nothing was checked"* ]] || false
}

@test "terms: an excluded prefix and a non-text file are not read" {
  config
  mkdir -p "$P/src/vendor"
  printf 'guaranteed\n' >"$P/src/vendor/a.md"
  printf 'guaranteed\n' >"$P/src/a.bin"
  printf 'plain\n' >"$P/src/b.md"
  stage
  terms
  [ "$status" -eq 0 ]
}

@test "terms: it reads the index, so a path deleted from the worktree neither crashes nor loses its allow entry" {
  config '[{"path": "src/a.md", "phrase": "not guaranteed", "reason": "a disclaimer"}]'
  printf 'not guaranteed\n' >"$P/src/a.md"
  stage
  rm "$P/src/a.md"
  terms
  [ "$status" -eq 0 ]
}

@test "terms: what is staged decides, not the worktree: an unstaged fix does not clear a staged word" {
  config
  printf 'guaranteed\n' >"$P/src/a.md"
  stage
  printf 'plain\n' >"$P/src/a.md"
  terms
  [ "$status" -eq 1 ]
}
