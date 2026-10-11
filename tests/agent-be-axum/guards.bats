#!/usr/bin/env bats
# The two guards agent-be-axum wires, on a repo laid out as setup leaves it: generated-guard refuses
# the sqlx cache and the exported spec, migration-guard keeps merged migrations append-only. Each
# probe that must block has one that must pass. The scripts are shared copies; the plugins they
# come from test every other case.

load helpers

setup() {
  ax_setup_env
  PROJ="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$PROJ/.claude" "$PROJ/.sqlx" "$PROJ/migrations" "$PROJ/src"
  cp "$TPL/.claude/agent-config.json" "$PROJ/.claude/agent-config.json"
  printf '{}\n' >"$PROJ/.sqlx/query-0a1b.json"
  printf '{}\n' >"$PROJ/openapi.json"
  printf 'pub fn f() {}\n' >"$PROJ/src/lib.rs"
  printf 'CREATE TABLE t (id int);\n' >"$PROJ/migrations/20261011000000_t.sql"
  git -C "$PROJ" init -q
  git -C "$PROJ" add -A
  git -C "$PROJ" commit -q -m init
  PROJ="$(cd "$PROJ" && pwd -P)"
}

@test "generated-guard: an edit to the sqlx cache is refused" {
  run_guard generated-guard.sh "$(edit_payload Edit "$PROJ/.sqlx/query-0a1b.json")"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"[generated-guard] BLOCKED: .sqlx/query-0a1b.json is generated output (.sqlx in generatedPaths)."* ]] || false
}

@test "generated-guard: an edit to openapi.json is refused" {
  run_guard generated-guard.sh "$(edit_payload Write "$PROJ/openapi.json")"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"[generated-guard] BLOCKED: openapi.json"* ]] || false
}

@test "generated-guard: source code passes" {
  run_guard generated-guard.sh "$(edit_payload Edit "$PROJ/src/lib.rs")"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

@test "migration-guard: a migration main already has is refused" {
  grep -q appendOnlyMigrationsDirs "$PLUGIN/scripts/migration-guard.sh" ||
    skip "migration-guard.sh has no append-only mode yet (agent-core's appendOnlyMigrationsDirs)"
  run_guard migration-guard.sh "$(edit_payload Edit "$PROJ/migrations/20261011000000_t.sql")"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"[migration-guard] BLOCKED: migrations/20261011000000_t.sql is already on main"* ]] || false
}

@test "migration-guard: a new migration, and one only on a work branch, pass" {
  run_guard migration-guard.sh "$(edit_payload Write "$PROJ/migrations/20261012000000_u.sql")"
  [ "$status" -eq 0 ]
  git -C "$PROJ" checkout -q -b work
  printf 'CREATE TABLE u (id int);\n' >"$PROJ/migrations/20261012000000_u.sql"
  git -C "$PROJ" add -A
  git -C "$PROJ" commit -q -m u
  run_guard migration-guard.sh "$(edit_payload Edit "$PROJ/migrations/20261012000000_u.sql")"
  [ "$status" -eq 0 ]
}
