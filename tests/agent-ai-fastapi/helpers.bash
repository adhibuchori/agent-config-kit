# Helpers for the agent-ai-fastapi tests. Every test builds its own temp repo under
# $BATS_TEST_TMPDIR from tests/fixtures/ai-fastapi, needs no network, and never writes inside this
# repository.
# shellcheck shell=bash
# The .bats files that load this read its variables, and bats's `run` sets output and status.
# shellcheck disable=SC2034,SC2154

bats_require_minimum_version 1.5.0

KIT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
PLUGIN="$KIT_ROOT/plugins/agent-ai-fastapi"
TPL="$PLUGIN/templates/ai-fastapi"
CORE="$KIT_ROOT/plugins/agent-core"
CORE_VERSION="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "$CORE/.claude-plugin/plugin.json")"
PLUGIN_VERSION="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "$PLUGIN/.claude-plugin/plugin.json")"
CORE_TPL="$CORE/templates/common"
GUARD="$PLUGIN/scripts/migration-guard.sh"
FIXTURES="$KIT_ROOT/tests/fixtures/ai-fastapi"
# The bash that runs the hook, as Claude Code's `bash "<script>"` would. HOOK_BASH=/bin/bash proves
# macOS's bash 3.2.
HOOK_BASH="${HOOK_BASH:-bash}"
# The write tools every stack guard is wired on (cd-conventions section 4).
WRITE_MATCHER='Write|Edit|MultiEdit|mcp__serena__(replace_content|replace_symbol_body|insert_after_symbol|insert_before_symbol|replace_in_files|rename_symbol|safe_delete_symbol)'

# A clean environment for every test: no plugin root, no workspace, git config in the temp dir.
ai_setup_env() {
  unset CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA CLAUDE_PROJECT_DIR AGENT_WORKSPACE_ROOT
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  export TMPDIR="$BATS_TEST_TMPDIR"
  # No Python bytecode written next to a template or a fixture: setup would install it.
  export PYTHONDONTWRITEBYTECODE=1
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"
  export GIT_CONFIG_NOSYSTEM=1
  printf '[user]\n\temail = test@example.invalid\n\tname = test\n[init]\n\tdefaultBranch = main\n[commit]\n\tgpgsign = false\n' \
    >"$GIT_CONFIG_GLOBAL"
}

# make_project <pipeline|service>: a committed git repo copied from the fixture; sets PROJ.
make_project() {
  PROJ="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$PROJ"
  cp -R "$FIXTURES/$1/." "$PROJ/"
  git -C "$PROJ" init -q
  git -C "$PROJ" add -A
  git -C "$PROJ" commit -q -m init
  PROJ="$(cd "$PROJ" && pwd -P)"
}

# The tool call Claude Code would send: edit_payload <tool> <file_path>
edit_payload() {
  printf '{"tool_name":"%s","tool_input":{"file_path":"%s","old_string":"a","new_string":"b"}}' "$1" "$2"
}

# serena_scope_payload <relative_path> [needle]: a replace_in_files that names a folder, not a file.
# The default needle occurs in the fixture revision, so the call would rewrite it.
serena_scope_payload() {
  printf '{"tool_name":"mcp__serena__replace_in_files","tool_input":{"relative_path":"%s","needle":"%s","repl":"b","mode":"literal"}}' \
    "$1" "${2:-down_revision}"
}

# run_guard <payload> [VAR=value ...]: the guard as Claude Code runs it, from the project.
run_guard() {
  local payload="$1"
  shift
  run --separate-stderr env CLAUDE_PROJECT_DIR="$PROJ" "$@" "$HOOK_BASH" "$GUARD" <<<"$payload"
}

# A PATH without python3 (and without jq unless asked): links to every other program on the system.
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
  [ -e "$dir/git" ] || ln -s "$(command -v git)" "$dir/git"
  if [ -n "$keep_jq" ]; then
    rm -f "$dir/jq"
    ln -s "$(command -v jq)" "$dir/jq"
  fi
}

# agent-core's engine, which /agent-ai-fastapi:setup and :sync call by bare name.
SETUP_BIN="$CORE/bin/agent-setup"
SYNC_BIN="$CORE/bin/agent-sync"
ai_engine() {
  [ -x "$SETUP_BIN" ] && [ -x "$SYNC_BIN" ] && [ -f "$CORE/libexec/agentkit.py" ]
}

# The arguments every engine call takes, for the project in $PROJ.
ai_args() {
  ARGS=(--templates "$PLUGIN/templates" --stack ai-fastapi --project "$PROJ")
}

# ai_setup [--answer id=value ...]: plan with these answers, then apply exactly that draft, as the
# setup command does on "go". Leaves the plan in $PLAN.
ai_setup() {
  ai_args
  run -0 --separate-stderr "$SETUP_BIN" plan "${ARGS[@]}" "$@"
  PLAN="$output"
  DIGEST="$(printf '%s\n' "$output" | sed -n 's/^digest \(sha256:[0-9a-f]\{64\}\)$/\1/p')"
  [ -n "$DIGEST" ]
  run -0 --separate-stderr "$SETUP_BIN" apply "${ARGS[@]}" "$@" --digest "$DIGEST"
}

# A python3 new enough for tomllib (3.11+), or empty.
toml_python() {
  local py
  for py in python3.14 python3.13 python3.12 python3.11 python3; do
    if command -v "$py" >/dev/null 2>&1 && "$py" -c 'import tomllib' 2>/dev/null; then
      command -v "$py"
      return 0
    fi
  done
  return 1
}
