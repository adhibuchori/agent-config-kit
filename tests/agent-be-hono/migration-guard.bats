#!/usr/bin/env bats
# migration-guard.sh as agent-be-hono runs it: the plugin-mode project gate, the block, what it lets
# through, its configuration, and its fail modes (bad payload, no python3, no JSON reader).

load helpers

setup() {
  be_setup_env
  make_drizzle_project
}

@test "template mode: an edit under src/db/migrations is refused with the drizzle-kit reason" {
  run_guard "$(edit_payload Edit "$PROJ/src/db/migrations/0000_init.sql")"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"[migration-guard] BLOCKED: src/db/migrations/0000_init.sql is drizzle-kit output"* ]]
  [ -z "$output" ]
}

@test "plugin mode, project not opted in: every call passes silently, even a migration edit" {
  run_guard "$(edit_payload Edit "$PROJ/src/db/migrations/0000_init.sql")" CLAUDE_PLUGIN_ROOT="$PLUGIN"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "plugin mode, not opted in: a payload that is not JSON is not even read" {
  run_guard '{not json' CLAUDE_PLUGIN_ROOT="$PLUGIN"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

@test "plugin mode, opted in by the setup lock: the migration edit is refused" {
  mkdir -p "$PROJ/.claude"
  printf '{}\n' >"$PROJ/.claude/agent-config-kit.lock"
  run_guard "$(edit_payload Write "$PROJ/src/db/migrations/0001_next.sql")" CLAUDE_PLUGIN_ROOT="$PLUGIN"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"[migration-guard] BLOCKED"* ]]
}

@test "plugin mode, opted in by .claude/agent-config.json: the migration edit is refused" {
  mkdir -p "$PROJ/.claude"
  printf '{}\n' >"$PROJ/.claude/agent-config.json"
  run_guard "$(edit_payload MultiEdit "$PROJ/src/db/migrations/0000_init.sql")" CLAUDE_PLUGIN_ROOT="$PLUGIN"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"drizzle-kit output"* ]]
}

@test "an edit outside the migrations folders is allowed" {
  run_guard "$(edit_payload Edit "$PROJ/src/modules/thing/thing.service.ts")"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  run_guard "$(edit_payload Write "$PROJ/src/db/schema/things.ts")"
  [ "$status" -eq 0 ]
}

@test "a relative file_path resolves against the project (the probe /agent-be-hono:setup runs)" {
  run_guard "$(edit_payload Edit src/db/migrations/0000_probe.sql)"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"src/db/migrations/0000_probe.sql is drizzle-kit output"* ]]
}

@test "migrationsDirs in .claude/agent-config.json replaces the default list whole" {
  mkdir -p "$PROJ/.claude" "$PROJ/db/out"
  printf '{"migrationsDirs": ["db/out/"]}\n' >"$PROJ/.claude/agent-config.json"
  run_guard "$(edit_payload Edit "$PROJ/db/out/0001.sql")" CLAUDE_PLUGIN_ROOT="$PLUGIN"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"db/out/0001.sql is drizzle-kit output"* ]]
  run_guard "$(edit_payload Edit "$PROJ/src/db/migrations/0000_init.sql")" CLAUDE_PLUGIN_ROOT="$PLUGIN"
  [ "$status" -eq 0 ]
}

@test "a migrations folder the repo does not have guards nothing" {
  rm -rf "$PROJ/src/db/migrations"
  run_guard "$(edit_payload Write "$PROJ/src/db/migrations/0000_init.sql")"
  [ "$status" -eq 0 ]
}

@test "the drizzle folder is guarded by default too" {
  mkdir -p "$PROJ/drizzle"
  run_guard "$(edit_payload Edit "$PROJ/drizzle/0000_x.sql")"
  [ "$status" -eq 2 ]
}

@test "without drizzle.config.* the reason is the generic one" {
  rm -f "$PROJ/drizzle.config.ts"
  run_guard "$(edit_payload Edit "$PROJ/src/db/migrations/0000_init.sql")"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"is a generated migration (src/db/migrations in migrationsDirs)"* ]]
}

@test "Serena replace_in_files that reaches a migrations folder is refused; a narrower one passes" {
  run_guard "$(serena_scope_payload src)"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"this replace_in_files reaches migrations"* ]]
  run_guard "$(serena_scope_payload src/modules)"
  [ "$status" -eq 0 ]
}

@test "Serena replace_in_files over the project passes when its needle is in no migration" {
  run_guard "$(serena_scope_payload src absentNeedle)"
  [ "$status" -eq 0 ]
  run_guard "$(serena_scope_payload "" things)"
  [ "$status" -eq 2 ]
}

# Hand-written migrations (goose, sqlx): db/migrations is an appendOnlyMigrationsDirs folder. main
# holds 00001; the work branch feat, checked out, adds 00002.
make_append_project() {
  PROJ="$BATS_TEST_TMPDIR/append"
  mkdir -p "$PROJ/db/migrations" "$PROJ/.claude" "$PROJ/internal/thing"
  git -C "$PROJ" init -q -b main
  printf '{"appendOnlyMigrationsDirs": ["db/migrations"]}\n' >"$PROJ/.claude/agent-config.json"
  printf -- '-- +goose Up\nCREATE TABLE things (id bigint PRIMARY KEY);\n' >"$PROJ/db/migrations/00001_init.sql"
  printf 'package thing\n' >"$PROJ/internal/thing/thing.go"
  git -C "$PROJ" add -A && git -C "$PROJ" commit -q -m init
  git -C "$PROJ" checkout -q -b feat
  printf -- '-- +goose Up\nALTER TABLE things ADD name text;\n' >"$PROJ/db/migrations/00002_name.sql"
  git -C "$PROJ" add -A && git -C "$PROJ" commit -q -m name
  PROJ="$(cd "$PROJ" && pwd -P)"
}

@test "append-only: a migration a protected branch already has is refused, naming the branch" {
  make_append_project
  run_guard "$(edit_payload Edit "$PROJ/db/migrations/00001_init.sql")"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"[migration-guard] BLOCKED: db/migrations/00001_init.sql is already on main, so a database may have run it."* ]]
  [[ "$stderr" == *"Write a new migration"* ]]
  [ -z "$output" ]
  # Plugin mode, opted in by the same agent-config.json.
  run_guard "$(edit_payload Write "$PROJ/db/migrations/00001_init.sql")" CLAUDE_PLUGIN_ROOT="$PLUGIN"
  [ "$status" -eq 2 ]
}

@test "append-only: a new migration, and one only the work branch has, stay editable" {
  make_append_project
  run_guard "$(edit_payload Write "$PROJ/db/migrations/00003_new.sql")"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  run_guard "$(edit_payload Edit "$PROJ/db/migrations/00002_name.sql")"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

@test "append-only: a file outside the folder, or a repo without the key, is not judged" {
  make_append_project
  run_guard "$(edit_payload Edit "$PROJ/internal/thing/thing.go")"
  [ "$status" -eq 0 ]
  # The default is an empty list: a merged migration there is the project's own business.
  rm "$PROJ/.claude/agent-config.json"
  run_guard "$(edit_payload Edit "$PROJ/db/migrations/00001_init.sql")"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

@test "append-only: a repo without a commit has nothing merged" {
  PROJ="$BATS_TEST_TMPDIR/fresh"
  mkdir -p "$PROJ/db/migrations" "$PROJ/.claude"
  git -C "$PROJ" init -q -b main
  printf '{"appendOnlyMigrationsDirs": ["db/migrations"]}\n' >"$PROJ/.claude/agent-config.json"
  printf 'SELECT 1;\n' >"$PROJ/db/migrations/00001_init.sql"
  PROJ="$(cd "$PROJ" && pwd -P)"
  run_guard "$(edit_payload Edit "$PROJ/db/migrations/00001_init.sql")"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

@test "append-only: a migration only origin's copy of a protected branch has is refused" {
  make_append_project
  # origin/dev, as last fetched, holds 00003; no local branch does.
  git -C "$PROJ" checkout -q -b scratch
  printf 'SELECT 3;\n' >"$PROJ/db/migrations/00003_remote.sql"
  git -C "$PROJ" add -A && git -C "$PROJ" commit -q -m remote
  git -C "$PROJ" update-ref refs/remotes/origin/dev HEAD
  git -C "$PROJ" checkout -q feat && git -C "$PROJ" branch -q -D scratch
  run_guard "$(edit_payload Write "$PROJ/db/migrations/00003_remote.sql")"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"db/migrations/00003_remote.sql is already on dev"* ]]
  # protectedBranches decides which branches count.
  printf '{"appendOnlyMigrationsDirs": ["db/migrations"], "protectedBranches": ["main"]}\n' >"$PROJ/.claude/agent-config.json"
  run_guard "$(edit_payload Write "$PROJ/db/migrations/00003_remote.sql")"
  [ "$status" -eq 0 ]
}

@test "append-only: a symlink to a merged migration is refused, since the write lands there" {
  make_append_project
  mkdir -p "$PROJ/notes"
  ln -s ../db/migrations/00001_init.sql "$PROJ/notes/init.sql"
  run_guard "$(edit_payload Edit "$PROJ/notes/init.sql")"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"db/migrations/00001_init.sql is already on main"* ]]
}

@test "append-only: ROOT below the git top level still finds the merged file" {
  make_append_project
  local top="$PROJ"
  mkdir -p "$top/svc"
  git -C "$top" mv db svc/db
  git -C "$top" mv .claude svc/.claude
  git -C "$top" commit -q -m move
  git -C "$top" checkout -q main && git -C "$top" merge -q --ff-only feat && git -C "$top" checkout -q -b next
  PROJ="$top/svc"
  run_guard "$(edit_payload Edit "$PROJ/db/migrations/00002_name.sql")"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"db/migrations/00002_name.sql is already on main"* ]]
}

@test "append-only fails closed: outside a git repo, whether the file merged cannot be told" {
  make_append_project
  rm -rf "$PROJ/.git"
  run_guard "$(edit_payload Edit "$PROJ/db/migrations/00002_name.sql")"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"git could not say whether a protected branch already has db/migrations/00002_name.sql"* ]]
}

@test "append-only: replace_in_files that reaches the folder is refused" {
  make_append_project
  run_guard "$(serena_scope_payload db)"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"this replace_in_files reaches migrations"* ]]
  run_guard "$(serena_scope_payload internal)"
  [ "$status" -eq 0 ]
}

@test "drizzle folders keep their own reason when the repo also lists an append-only folder" {
  mkdir -p "$PROJ/.claude" "$PROJ/db/sql"
  printf '{"appendOnlyMigrationsDirs": ["db/sql"]}\n' >"$PROJ/.claude/agent-config.json"
  run_guard "$(edit_payload Edit "$PROJ/src/db/migrations/0000_init.sql")"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"src/db/migrations/0000_init.sql is drizzle-kit output"* ]]
  run_guard "$(edit_payload Write "$PROJ/db/sql/0001_new.sql")"
  [ "$status" -eq 0 ]
}

@test "fail closed: a payload that is not one JSON object is refused once opted in" {
  mkdir -p "$PROJ/.claude"
  printf '{}\n' >"$PROJ/.claude/agent-config-kit.lock"
  run_guard '{not json' CLAUDE_PLUGIN_ROOT="$PLUGIN"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"[migration-guard] BLOCKED: this tool call's payload is not a JSON object"* ]]
  run_guard '[1,2]'
  [ "$status" -eq 2 ]
}

@test "fail closed: with neither python3 nor jq every call is refused" {
  restricted_path "$BATS_TEST_TMPDIR/nobin"
  run_guard "$(edit_payload Edit "$PROJ/src/modules/thing/thing.service.ts")" PATH="$BATS_TEST_TMPDIR/nobin"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"neither python3 nor jq is installed"* ]]
}

@test "jq without python3: a plain edit is still judged; replace_in_files is refused" {
  command -v jq >/dev/null || skip "jq is not installed"
  restricted_path "$BATS_TEST_TMPDIR/jqbin" keep-jq
  run_guard "$(edit_payload Edit "$PROJ/src/db/migrations/0000_init.sql")" PATH="$BATS_TEST_TMPDIR/jqbin"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"drizzle-kit output"* ]]
  run_guard "$(edit_payload Edit "$PROJ/src/modules/thing/thing.service.ts")" PATH="$BATS_TEST_TMPDIR/jqbin"
  [ "$status" -eq 0 ]
  run_guard "$(serena_scope_payload src/modules)" PATH="$BATS_TEST_TMPDIR/jqbin"
  [ "$status" -eq 2 ]
}

@test "stdout stays empty and nothing is written under the plugin root" {
  local copy="$BATS_TEST_TMPDIR/plugin-copy" before after
  cp -R "$PLUGIN" "$copy"
  mkdir -p "$PROJ/.claude"
  printf '{}\n' >"$PROJ/.claude/agent-config-kit.lock"
  before="$(cd "$copy" && find . | LC_ALL=C sort)"
  run --separate-stderr env CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_PLUGIN_ROOT="$copy" \
    CLAUDE_PLUGIN_DATA="$BATS_TEST_TMPDIR/data" "$HOOK_BASH" "$copy/scripts/migration-guard.sh" \
    <<<"$(edit_payload Edit "$PROJ/src/db/migrations/0000_init.sql")"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  after="$(cd "$copy" && find . | LC_ALL=C sort)"
  [ "$before" = "$after" ]
}

@test "scripts/lib.sh has the same bytes as agent-core's copy" {
  [ -f "$KIT_ROOT/plugins/agent-core/scripts/lib.sh" ] || skip "agent-core's lib.sh is not built yet"
  cmp "$PLUGIN/scripts/lib.sh" "$KIT_ROOT/plugins/agent-core/scripts/lib.sh"
}

@test "hooks.json wires the guard on the write tools, quoted, through bash, with a 10 s timeout" {
  run python3 - "$PLUGIN/hooks/hooks.json" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1]))
assert set(d["hooks"]) == {"PreToolUse"}, d["hooks"].keys()
(entry,) = d["hooks"]["PreToolUse"]
(hook,) = entry["hooks"]
assert hook == {"type": "command", "command": 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/migration-guard.sh"', "timeout": 10}, hook
m = re.compile("^(?:%s)$" % entry["matcher"])
for tool in ("Write", "Edit", "MultiEdit", "mcp__serena__replace_in_files", "mcp__serena__replace_symbol_body"):
    assert m.match(tool), tool
for tool in ("Bash", "Read", "mcp__serena__find_symbol", "mcp__db-prod__execute_sql"):
    assert not m.match(tool), tool
print("ok")
PY
  [ "$status" -eq 0 ]
  [ "$output" = ok ]
}

@test "hook scripts are executable and parse under the bash that runs them" {
  for f in "$PLUGIN"/scripts/*.sh; do
    [ -x "$f" ]
    "$HOOK_BASH" -n "$f"
  done
}
