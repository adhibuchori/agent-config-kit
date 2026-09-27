#!/usr/bin/env bats
# migration-guard.sh as agent-ai-fastapi runs it: the plugin-mode project gate, the Alembic block, what
# it lets through, the pipeline shape switching it on, its configuration, and its fail modes (bad
# payload, no python3, no JSON reader).

load helpers

setup() {
  ai_setup_env
  make_project pipeline
}

@test "template mode: an edit to an Alembic revision is refused with the autogenerate reason" {
  run_guard "$(edit_payload Edit "$PROJ/alembic/versions/0001_initial.py")"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"[migration-guard] BLOCKED: alembic/versions/0001_initial.py is an Alembic revision"* ]] || false
  [[ "$stderr" == *"alembic revision --autogenerate"* ]] || false
  [ -z "$output" ]
}

@test "plugin mode, project not opted in: every call passes silently, even a revision edit" {
  run_guard "$(edit_payload Edit "$PROJ/alembic/versions/0001_initial.py")" CLAUDE_PLUGIN_ROOT="$PLUGIN"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "plugin mode, not opted in: a payload that is not JSON is not even read" {
  run_guard '{not json' CLAUDE_PLUGIN_ROOT="$PLUGIN"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

@test "plugin mode, opted in by the setup lock: the revision edit is refused" {
  mkdir -p "$PROJ/.claude"
  printf '{}\n' >"$PROJ/.claude/agent-config-kit.lock"
  run_guard "$(edit_payload Write "$PROJ/alembic/versions/0002_next.py")" CLAUDE_PLUGIN_ROOT="$PLUGIN"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"alembic/versions/0002_next.py is an Alembic revision"* ]] || false
}

@test "plugin mode, opted in by .claude/agent-config.json: the revision edit is refused" {
  mkdir -p "$PROJ/.claude"
  printf '{}\n' >"$PROJ/.claude/agent-config.json"
  run_guard "$(edit_payload MultiEdit "$PROJ/alembic/versions/0001_initial.py")" CLAUDE_PLUGIN_ROOT="$PLUGIN"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"is an Alembic revision"* ]] || false
}

@test "the models, env.py, script.py.mako and alembic.ini stay editable" {
  local f
  for f in src/app/db/models.py alembic/env.py alembic/script.py.mako alembic.ini src/app/main.py; do
    run_guard "$(edit_payload Edit "$PROJ/$f")"
    [ "$status" -eq 0 ]
    [ -z "$stderr" ]
  done
}

@test "a relative file_path resolves against the project (the probe /agent-ai-fastapi:setup runs)" {
  run_guard "$(edit_payload Edit alembic/versions/0000_probe.py)"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"alembic/versions/0000_probe.py is an Alembic revision"* ]] || false
}

@test "the other Alembic layouts in the defaults are guarded too" {
  local d
  for d in migrations/versions src/app/db/migrations/versions; do
    mkdir -p "$PROJ/$d"
    run_guard "$(edit_payload Write "$PROJ/$d/0003_x.py")"
    [ "$status" -eq 2 ]
    [[ "$stderr" == *"$d/0003_x.py is an Alembic revision"* ]] || false
  done
}

@test "service shape: a repo with no migrations folder is not affected" {
  rm -rf "$PROJ"
  make_project service
  run_guard "$(edit_payload Write "$PROJ/alembic/versions/0001_initial.py")"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  run_guard "$(edit_payload Edit "$PROJ/src/app/modules/chat/service.py")"
  [ "$status" -eq 0 ]
}

@test "without alembic.ini the folder is still guarded, with the generic reason" {
  rm "$PROJ/alembic.ini"
  run_guard "$(edit_payload Edit "$PROJ/alembic/versions/0001_initial.py")"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"is a generated migration (alembic/versions in migrationsDirs)"* ]] || false
}

@test "migrationsDirs in .claude/agent-config.json replaces the default list whole" {
  mkdir -p "$PROJ/.claude" "$PROJ/db/revisions"
  printf '{"migrationsDirs": ["db/revisions/"]}\n' >"$PROJ/.claude/agent-config.json"
  run_guard "$(edit_payload Edit "$PROJ/db/revisions/0001.py")" CLAUDE_PLUGIN_ROOT="$PLUGIN"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"db/revisions/0001.py is an Alembic revision"* ]] || false
  run_guard "$(edit_payload Edit "$PROJ/alembic/versions/0001_initial.py")" CLAUDE_PLUGIN_ROOT="$PLUGIN"
  [ "$status" -eq 0 ]
}

@test "an empty migrationsDirs turns the guard off in a repo that has migrations" {
  mkdir -p "$PROJ/.claude"
  printf '{"migrationsDirs": []}\n' >"$PROJ/.claude/agent-config.json"
  run_guard "$(edit_payload Edit "$PROJ/alembic/versions/0001_initial.py")" CLAUDE_PLUGIN_ROOT="$PLUGIN"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  run_guard "$(serena_scope_payload alembic)" CLAUDE_PLUGIN_ROOT="$PLUGIN"
  [ "$status" -eq 0 ]
}

@test "a Serena replace_in_files that reaches the revisions is refused; a narrowed one passes" {
  run_guard "$(serena_scope_payload alembic)"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"this replace_in_files reaches generated migrations"* ]] || false
  run_guard '{"tool_name":"mcp__serena__replace_in_files","tool_input":{"needle":"down_revision","repl":"b","mode":"literal"}}'
  [ "$status" -eq 2 ]
  run_guard "$(serena_scope_payload src)"
  [ "$status" -eq 0 ]
}

@test "a file outside the project is not this repo's to guard" {
  run_guard "$(edit_payload Write "$BATS_TEST_TMPDIR/elsewhere/alembic/versions/x.py")"
  [ "$status" -eq 0 ]
}

@test "fail closed: a payload that is not one JSON object is refused" {
  local p
  for p in '{not json' '[1,2]' ''; do
    run_guard "$p"
    [ "$status" -eq 2 ]
    [[ "$stderr" == *"payload is not a JSON object"* ]] || false
  done
}

@test "without python3, jq alone still reads the payload and the config" {
  restricted_path "$BATS_TEST_TMPDIR/bin" keep-jq
  run_guard "$(edit_payload Edit "$PROJ/alembic/versions/0001_initial.py")" PATH="$BATS_TEST_TMPDIR/bin"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"is an Alembic revision"* ]] || false
  run_guard "$(edit_payload Edit "$PROJ/src/app/db/models.py")" PATH="$BATS_TEST_TMPDIR/bin"
  [ "$status" -eq 0 ]
}

@test "without python3, a replace_in_files whose reach cannot be worked out is refused" {
  restricted_path "$BATS_TEST_TMPDIR/bin" keep-jq
  run_guard "$(serena_scope_payload src)" PATH="$BATS_TEST_TMPDIR/bin"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"[migration-guard] BLOCKED"* ]] || false
}

@test "with neither python3 nor jq, the guard refuses instead of guessing" {
  restricted_path "$BATS_TEST_TMPDIR/bin"
  run_guard "$(edit_payload Edit "$PROJ/src/app/db/models.py")" PATH="$BATS_TEST_TMPDIR/bin"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"neither python3 nor jq is installed"* ]] || false
}

@test "the guard writes nothing into the plugin folder or the project" {
  mkdir -p "$PROJ/.claude"
  printf '{}\n' >"$PROJ/.claude/agent-config-kit.lock"
  touch "$BATS_TEST_TMPDIR/marker"
  sleep 1
  run_guard "$(edit_payload Edit "$PROJ/alembic/versions/0001_initial.py")" \
    CLAUDE_PLUGIN_ROOT="$PLUGIN" CLAUDE_PLUGIN_DATA="$BATS_TEST_TMPDIR/data"
  [ "$status" -eq 2 ]
  run find "$PLUGIN" "$PROJ" -newer "$BATS_TEST_TMPDIR/marker" -not -path "$PROJ/.git/*" -not -path "$PROJ/.git"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run git -C "$PROJ" status --porcelain --untracked-files=all
  [ "$output" = "?? .claude/agent-config-kit.lock" ]
}
