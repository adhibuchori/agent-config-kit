#!/usr/bin/env bats
# actions/quality-gate/scripts/diff-scan.sh: only the lines a branch adds, never removed or header
# lines, with the path and line number; exit 2 when the diff cannot be read.

load helpers

setup() {
  ci_isolate
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO" && cd "$REPO" || return 1
  git init -q -b dev .
  printf 'one\ntwo\nold secret_marker\n' >a.ts
  git add -A && git commit -q -m base
  git checkout -q -b feature
}

scan() {
  run --separate-stderr bash "$QG/diff-scan.sh" dev "$@"
}

@test "diff-scan: an added line matches with its path and line number" {
  printf 'one\ntwo\nold secret_marker\nnew secret_marker\n' >a.ts
  git commit -qam add
  scan 'secret_marker' '*.ts'
  [ "$status" -eq 1 ]
  [ "$output" = "a.ts:4: new secret_marker" ]
}

@test "diff-scan: a removed or unchanged line never matches" {
  printf 'one\ntwo\n' >a.ts
  git commit -qam remove
  scan 'secret_marker' '*.ts'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "diff-scan: an added line whose text starts with +++ is still content" {
  printf '++ x marker\n' >b.ts
  git add b.ts && git commit -qm plus
  scan 'marker' '*.ts'
  [ "$status" -eq 1 ]
  [ "$output" = "b.ts:1: ++ x marker" ]
}

@test "diff-scan: the regex reads the text, never the path" {
  mkdir -p marker && printf 'clean\n' >marker/c.ts
  git add -A && git commit -qm path
  scan 'marker' '*.ts'
  [ "$status" -eq 0 ]
}

@test "diff-scan: pathspecs limit the files, excludes included" {
  printf 'hit marker\n' >c.test.ts
  printf 'hit marker\n' >c.md
  git add -A && git commit -qm files
  scan 'marker' '*.ts' ':(exclude)*.test.*'
  [ "$status" -eq 0 ]
}

@test "diff-scan: more than 20 hits print the first 20 and a count" {
  for i in $(seq 1 25); do printf 'marker %s\n' "$i"; done >d.ts
  git add -A && git commit -qm many
  scan 'marker' '*.ts'
  [ "$status" -eq 1 ]
  [ "${#lines[@]}" -eq 21 ]
  [ "${lines[20]}" = "... and 5 more" ]
}

@test "diff-scan: an unknown base or too few arguments exits 2" {
  run --separate-stderr bash "$QG/diff-scan.sh" nope marker '*.ts'
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"could not read the diff"* ]]
  run --separate-stderr bash "$QG/diff-scan.sh" dev marker
  [ "$status" -eq 2 ]
}
