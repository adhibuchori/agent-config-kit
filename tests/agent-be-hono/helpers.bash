# Helpers for the agent-be-hono tests. Every test builds its own temp repo under $BATS_TEST_TMPDIR,
# needs no network, and never writes inside this repository.
# shellcheck shell=bash

bats_require_minimum_version 1.5.0

# The .bats files that load this file read these paths.
# shellcheck disable=SC2034
{
  KIT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
  PLUGIN="$KIT_ROOT/plugins/agent-be-hono"
  TPL="$PLUGIN/templates/be-hono"
  GUARD="$PLUGIN/scripts/migration-guard.sh"
  FIXTURES="$KIT_ROOT/tests/fixtures/be-hono"
  TEMPLATES="$PLUGIN/templates"
  CORE="$KIT_ROOT/plugins/agent-core"
}
# The bash that runs the hook, as Claude Code's `bash "<script>"` would. HOOK_BASH=/bin/bash proves
# macOS's bash 3.2.
HOOK_BASH="${HOOK_BASH:-bash}"

# A clean environment for every test: no plugin root, no workspace, hook state in the temp dir.
be_setup_env() {
  unset CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA AGENT_WORKSPACE_ROOT AGENT_HOOK_STATE_DIR
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  export TMPDIR="$BATS_TEST_TMPDIR"
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"
  export GIT_CONFIG_NOSYSTEM=1
  printf '[user]\n\temail = test@example.invalid\n\tname = test\n[init]\n\tdefaultBranch = main\n[commit]\n\tgpgsign = false\n' \
    >"$GIT_CONFIG_GLOBAL"
}

# A Drizzle project: git repo, drizzle.config.ts and src/db/migrations with one committed migration.
make_drizzle_project() {
  PROJ="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$PROJ/src/db/migrations" "$PROJ/src/db/schema" "$PROJ/src/modules/thing"
  git -C "$PROJ" init -q
  printf 'export default { schema: "./src/db/schema", out: "./src/db/migrations" };\n' >"$PROJ/drizzle.config.ts"
  printf 'CREATE TABLE "things" ("id" text PRIMARY KEY);\n' >"$PROJ/src/db/migrations/0000_init.sql"
  printf 'export const x = 1;\n' >"$PROJ/src/modules/thing/thing.service.ts"
  git -C "$PROJ" add -A
  git -C "$PROJ" commit -q -m init
  PROJ="$(cd "$PROJ" && pwd -P)"
}

# A Bun + Hono + Drizzle API before setup: the user's own CLAUDE.md and package.json (with a lint
# script of their own), a schema and one committed migration. No AGENTS.md, SSOT.md or .claude/.
make_api_project() {
  APP="$BATS_TEST_TMPDIR/api"
  mkdir -p "$APP/src/db/migrations" "$APP/src/db/schema"
  cp "$FIXTURES/schema/owners.ts" "$APP/src/db/schema/"
  printf 'CREATE TABLE "owners" ("id" text PRIMARY KEY, "name" text NOT NULL);\n' \
    >"$APP/src/db/migrations/0000_init.sql"
  printf 'export default { schema: "./src/db/schema", out: "./src/db/migrations", dialect: "postgresql" };\n' \
    >"$APP/drizzle.config.ts"
  printf '# Toy API\n\nOur own notes, kept by setup.\n' >"$APP/CLAUDE.md"
  cat >"$APP/package.json" <<'JSON'
{
  "name": "toy-api",
  "private": true,
  "scripts": {
    "dev": "bun run --hot src/index.ts",
    "lint": "eslint ."
  },
  "dependencies": {
    "drizzle-orm": "0.44.0",
    "hono": "4.9.0"
  }
}
JSON
  git -C "$APP" init -q
  git -C "$APP" add -A
  git -C "$APP" commit -q -m init
  APP="$(cd "$APP" && pwd -P)"
}

# The tool call Claude Code would send: edit_payload <tool> <file_path>
edit_payload() {
  printf '{"tool_name":"%s","tool_input":{"file_path":"%s","old_string":"a","new_string":"b"}}' "$1" "$2"
}

# serena_scope_payload <relative_path> [needle]: a replace_in_files that names a folder, not a file.
# The default needle occurs in the fixture migration, so the call would rewrite it.
serena_scope_payload() {
  printf '{"tool_name":"mcp__serena__replace_in_files","tool_input":{"relative_path":"%s","needle":"%s","repl":"b","mode":"literal"}}' \
    "$1" "${2:-things}"
}

# run_guard <payload> [VAR=value ...]: the guard as Claude Code runs it, from the project.
run_guard() {
  local payload="$1"
  shift
  run --separate-stderr env CLAUDE_PROJECT_DIR="$PROJ" "$@" "$HOOK_BASH" "$GUARD" <<<"$payload"
}

# A PATH without python3 (and without jq when asked): links to every other program on the system.
# restricted_path <dir> [keep-jq]
restricted_path() {
  local dir="$1" keep_jq="${2:-}" src f name
  mkdir -p "$dir"
  for src in /usr/local/bin /usr/bin /bin /usr/sbin /sbin; do
    [ -d "$src" ] || continue
    for f in "$src"/*; do
      name="${f##*/}"
      case "$name" in
      python | python3 | python3.* | python2* | jq) continue ;;
      esac
      [ -e "$dir/$name" ] || ln -s "$f" "$dir/$name"
    done
  done
  # git may live elsewhere (Homebrew); the hooks need it.
  if [ ! -e "$dir/git" ]; then ln -s "$(command -v git)" "$dir/git"; fi
  if [ -n "$keep_jq" ]; then
    rm -f "$dir/jq"
    ln -s "$(command -v jq)" "$dir/jq"
  fi
}
