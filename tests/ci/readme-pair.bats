#!/usr/bin/env bats
# scripts/readme-pair.mjs: README.md and README.id.md change together, or not at all.

load helpers

setup() {
  ci_isolate
  need_node
  R="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$R"
  printf 'en\n' >"$R/README.md"
  printf 'id\n' >"$R/README.id.md"
  printf 'x\n' >"$R/other.md"
  git -C "$R" init -q -b main && git -C "$R" add -A && git -C "$R" commit -q -m base
  BASE="$(git -C "$R" rev-parse HEAD)"
}

pair() { node "$KIT_ROOT/scripts/readme-pair.mjs" --root "$R" "$@"; }
commit() { git -C "$R" add -A && git -C "$R" commit -q -m change; }

@test "neither README changed: pass" {
  printf 'y\n' >>"$R/other.md" && commit
  run -0 pair --base "$BASE"
  [[ "$output" == *"neither README changed"* ]] || false
}

@test "both READMEs changed: pass" {
  printf 'more\n' >>"$R/README.md" && printf 'lagi\n' >>"$R/README.id.md" && commit
  run -0 pair --base "$BASE"
  [[ "$output" == *"both READMEs changed"* ]] || false
}

@test "only README.md changed: fail and name the missing file" {
  printf 'more\n' >>"$R/README.md" && commit
  run -1 pair --base "$BASE"
  [[ "$output" == *"README.md changed"*"README.id.md did not"* ]] || false
}

@test "only README.id.md changed: fail and name the missing file" {
  printf 'lagi\n' >>"$R/README.id.md" && commit
  run -1 pair --base "$BASE"
  [[ "$output" == *"README.id.md changed"*"README.md did not"* ]] || false
}

@test "a change spread over two commits still counts as both" {
  printf 'more\n' >>"$R/README.md" && commit
  printf 'lagi\n' >>"$R/README.id.md" && commit
  run -0 pair --base "$BASE"
}

@test "a base it cannot resolve is a usage error" {
  run -2 pair --base does-not-exist
  [[ "$output" == *"cannot diff against does-not-exist"* ]] || false
}

@test "no --base is a usage error" {
  run -2 pair
}
