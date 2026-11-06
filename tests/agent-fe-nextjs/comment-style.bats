#!/usr/bin/env bats
# .github/scripts/check-comment-style.ts as a repo runs it: a tracked file another session deleted
# from a shared checkout is a deletion in progress, not a crash, and the files left are still read.

load helpers

setup() {
  command -v bun >/dev/null 2>&1 || skip "bun is not installed"
  REPO="$BATS_TEST_TMPDIR/app"
  mkdir -p "$REPO/.github/scripts"
  git -C "$REPO" init -q -b main
  cp "$STACK_DIR/.github/scripts/check-comment-style.ts" "$REPO/.github/scripts/"
}

style() {
  # shellcheck disable=SC2016 # $1 expands in the child shell
  run --separate-stderr bash -c 'cd "$1" && bun run .github/scripts/check-comment-style.ts' _ "$REPO"
}

@test "a tracked file gone from the worktree is skipped; the rest are still read" {
  printf 'export const a = 1;\n' >"$REPO/gone.ts"
  printf 'export const b = 2;\n' >"$REPO/kept.ts"
  git -C "$REPO" add -A
  rm "$REPO/gone.ts"
  style
  [ "$status" -eq 0 ]
  printf 'export const b = 2;\n// a note\n' >"$REPO/kept.ts"
  style
  [ "$status" -ne 0 ]
  [[ "$output" == *'kept.ts:2'* ]] || false
}
