# Helpers for the agent-be-go tests. Every test builds its own temp repo under $BATS_TEST_TMPDIR
# from tests/fixtures/be-go, needs no network and no Go toolchain (the check scripts get stub
# commands on PATH), and never writes inside this repository.
# shellcheck shell=bash
# The .bats files that load this read its variables, and bats's `run` sets output and status.
# shellcheck disable=SC2034,SC2154

bats_require_minimum_version 1.5.0

KIT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
PLUGIN="$KIT_ROOT/plugins/agent-be-go"
TPL="$PLUGIN/templates/be-go"
CORE="$KIT_ROOT/plugins/agent-core"
CORE_TPL="$CORE/templates/common"
CORE_VERSION="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "$CORE/.claude-plugin/plugin.json")"
PLUGIN_VERSION="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "$PLUGIN/.claude-plugin/plugin.json")"
FIXTURES="$KIT_ROOT/tests/fixtures/be-go"
MIGRATION_GUARD="$PLUGIN/scripts/migration-guard.sh"
GENERATED_GUARD="$PLUGIN/scripts/generated-guard.sh"
# The bash that runs the hooks, as Claude Code's `bash "<script>"` would. HOOK_BASH=/bin/bash proves
# macOS's bash 3.2.
HOOK_BASH="${HOOK_BASH:-bash}"
# The write tools every stack guard is wired on.
WRITE_MATCHER='Write|Edit|MultiEdit|mcp__serena__(replace_content|replace_symbol_body|insert_after_symbol|insert_before_symbol|replace_in_files|rename_symbol|safe_delete_symbol)'
# The stack plugins this one refuses to share a repo with.
CONFLICTS='agent-ai-fastapi agent-be-axum agent-be-hono agent-docs-nextra agent-fe-nextjs agent-fe-nextjs-static agent-ios-swiftui'

# A clean environment for every test: no plugin root, no workspace, git config in the temp dir.
go_setup_env() {
  unset CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA CLAUDE_PROJECT_DIR AGENT_WORKSPACE_ROOT AGENT_HOOK_STATE_DIR
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE TEST_DATABASE_URL TEST_POOLER_DATABASE_URL MIGRATIONS_BASE
  export TMPDIR="$BATS_TEST_TMPDIR"
  export PYTHONDONTWRITEBYTECODE=1
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"
  export GIT_CONFIG_NOSYSTEM=1
  printf '[user]\n\temail = test@example.invalid\n\tname = test\n[init]\n\tdefaultBranch = main\n[commit]\n\tgpgsign = false\n' \
    >"$GIT_CONFIG_GLOBAL"
}

# make_project: a committed git repo copied from the fixture service (its own go.mod, a command and
# one goose migration); sets PROJ.
make_project() {
  PROJ="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$PROJ"
  cp -R "$FIXTURES/service/." "$PROJ/"
  git -C "$PROJ" init -q
  git -C "$PROJ" add -A
  git -C "$PROJ" commit -q -m init
  PROJ="$(cd "$PROJ" && pwd -P)"
}

# The tool call Claude Code would send: edit_payload <tool> <file_path>
edit_payload() {
  printf '{"tool_name":"%s","tool_input":{"file_path":"%s","old_string":"a","new_string":"b"}}' "$1" "$2"
}

# run_hook <script> <payload> [VAR=value ...]: a guard as Claude Code runs it, from the project.
run_hook() {
  local script="$1" payload="$2"
  shift 2
  run --separate-stderr env CLAUDE_PROJECT_DIR="$PROJ" "$@" "$HOOK_BASH" "$script" <<<"$payload"
}

# agent-core's engine, which /agent-be-go:setup and :sync call by bare name.
SETUP_BIN="$CORE/bin/agent-setup"
SYNC_BIN="$CORE/bin/agent-sync"
go_engine() {
  [ -x "$SETUP_BIN" ] && [ -x "$SYNC_BIN" ] && [ -f "$CORE/libexec/agentkit.py" ]
}

# The arguments every engine call takes, for the project in $PROJ, plus agent-core's language
# answer: go once agent-core offers it, else the engine's recommended value.
go_args() {
  ARGS=(--templates "$PLUGIN/templates" --stack be-go --project "$PROJ")
  if python3 -c 'import json, sys; q = [q for q in json.load(open(sys.argv[1]))["questions"] if q["id"] == "language"]; sys.exit(0 if q and "go" in q[0]["choices"] else 1)' \
    "$CORE_TPL/_kit/setup.json"; then
    ARGS+=(--answer language=go)
  fi
}

# go_setup [--answer id=value ...]: plan with these answers, then apply exactly that draft, as the
# setup command does on "go". Leaves the plan in $PLAN.
go_setup() {
  go_args
  run -0 --separate-stderr "$SETUP_BIN" plan "${ARGS[@]}" "$@"
  PLAN="$output"
  DIGEST="$(printf '%s\n' "$output" | sed -n 's/^digest \(sha256:[0-9a-f]\{64\}\)$/\1/p')"
  [ -n "$DIGEST" ]
  run -0 --separate-stderr "$SETUP_BIN" apply "${ARGS[@]}" "$@" --digest "$DIGEST"
}

# stub_bin <name> <body>: an executable named <name> in $STUBS (first on PATH) that runs <body>.
stub_bin() {
  STUBS="${STUBS:-$BATS_TEST_TMPDIR/stubs}"
  mkdir -p "$STUBS"
  printf '#!/usr/bin/env bash\n%s\n' "$2" >"$STUBS/$1"
  chmod +x "$STUBS/$1"
}

# install_scripts <path>...: template files copied into the toy repo $REPO at the same path, mode kept.
install_scripts() {
  local rel
  for rel in "$@"; do
    mkdir -p "$REPO/$(dirname "$rel")"
    cp -p "$TPL/$rel" "$REPO/$rel"
  done
}

# code_lines <file>: lines that are neither blank nor only a // comment, the way revive's
# file-length-limit counts them with skip-comments and skip-blank-lines (block comments aside).
code_lines() {
  grep -cvE '^[[:space:]]*(//.*)?$' "$1"
}
