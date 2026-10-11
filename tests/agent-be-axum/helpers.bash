# Helpers for the agent-be-axum tests. Every test builds its own temp repo under $BATS_TEST_TMPDIR,
# needs no network and no Rust toolchain (a cargo stub stands in where a script calls cargo), and
# never writes inside this repository.
# shellcheck shell=bash
# The .bats files that load this read its variables, and bats's `run` sets output and status.
# shellcheck disable=SC2034,SC2154

bats_require_minimum_version 1.5.0

KIT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
PLUGIN="$KIT_ROOT/plugins/agent-be-axum"
TPL="$PLUGIN/templates/be-axum"
CORE="$KIT_ROOT/plugins/agent-core"
CORE_TPL="$CORE/templates/common"
FIXTURES="$KIT_ROOT/tests/fixtures/be-axum"
CORE_VERSION="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "$CORE/.claude-plugin/plugin.json")"
PLUGIN_VERSION="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "$PLUGIN/.claude-plugin/plugin.json")"
SETUP_BIN="$CORE/bin/agent-setup"
SYNC_BIN="$CORE/bin/agent-sync"
# The bash that runs a hook, as Claude Code's `bash "<script>"` would. HOOK_BASH=/bin/bash proves
# macOS's bash 3.2.
HOOK_BASH="${HOOK_BASH:-bash}"
# The write tools every stack guard is wired on.
WRITE_MATCHER='Write|Edit|MultiEdit|mcp__serena__(replace_content|replace_symbol_body|insert_after_symbol|insert_before_symbol|replace_in_files|rename_symbol|safe_delete_symbol)'

# A clean environment for every test: no plugin root, no workspace, git config in the temp dir.
ax_setup_env() {
  unset CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA CLAUDE_PROJECT_DIR AGENT_WORKSPACE_ROOT AGENT_HOOK_STATE_DIR
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE DATABASE_URL TEST_POOLER_DATABASE_URL
  export TMPDIR="$BATS_TEST_TMPDIR"
  export PYTHONDONTWRITEBYTECODE=1
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"
  export GIT_CONFIG_NOSYSTEM=1
  printf '[user]\n\temail = test@example.invalid\n\tname = test\n[init]\n\tdefaultBranch = main\n[commit]\n\tgpgsign = false\n' \
    >"$GIT_CONFIG_GLOBAL"
}

# A git repo for check-script probes; sets REPO.
make_repo() {
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO/scripts/check"
  git -C "$REPO" init -q
  REPO="$(cd "$REPO" && pwd -P)"
}

# install <template path>...: copies template files into $REPO at the same path, mode kept.
install() {
  local rel
  for rel in "$@"; do
    mkdir -p "$REPO/$(dirname "$rel")"
    cp -p "$TPL/$rel" "$REPO/$rel"
  done
}

# commit_all <message>: stages and commits everything in $REPO.
commit_all() {
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "$1"
}

# stub <name> <body>: an executable on a PATH of stubs that $REPO's scripts find first.
stub() {
  mkdir -p "$BATS_TEST_TMPDIR/stubs"
  printf '#!/bin/sh\n%s\n' "$2" >"$BATS_TEST_TMPDIR/stubs/$1"
  chmod +x "$BATS_TEST_TMPDIR/stubs/$1"
  export PATH="$BATS_TEST_TMPDIR/stubs:$PATH"
}

# rs <path> <lines...>: writes one Rust file in $REPO, a line per argument.
rs() {
  local path="$1"
  shift
  mkdir -p "$REPO/$(dirname "$path")"
  printf '%s\n' "$@" >"$REPO/$path"
}

# source_check: rust-source.mjs as the gate runs it, from $REPO.
source_check() {
  run --separate-stderr node "$REPO/scripts/check/rust-source.mjs"
}

# make_project <empty|crate>: a committed repo before setup; sets PROJ.
make_project() {
  PROJ="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$PROJ"
  if [ "$1" = crate ]; then
    cp -R "$FIXTURES/crate/." "$PROJ/"
  else
    printf '# A new service\n' >"$PROJ/README.md"
  fi
  git -C "$PROJ" init -q
  git -C "$PROJ" add -A
  git -C "$PROJ" commit -q -m init
  PROJ="$(cd "$PROJ" && pwd -P)"
}

ax_engine() {
  [ -x "$SETUP_BIN" ] && [ -x "$SYNC_BIN" ] && [ -f "$CORE/libexec/agentkit.py" ]
}

ax_args() {
  ARGS=(--templates "$PLUGIN/templates" --stack be-axum --project "$PROJ")
}

# The answer for agent-core's language question: rust once agent-core offers it, else its default.
language_answer() {
  "$SETUP_BIN" questions "${ARGS[@]}" --json | python3 -c '
import json, sys
qs = [q for q in json.load(sys.stdin)["questions"] if q["plugin"] == "agent-core" and q["id"] == "language"]
print("language=" + ("rust" if qs and "rust" in qs[0]["choices"] else qs[0]["recommended"] if qs else ""))'
}

# ax_setup [--answer id=value ...]: plan with these answers, then apply exactly that draft, as the
# setup command does on "go". Leaves the plan in $PLAN.
ax_setup() {
  ax_args
  local lang
  lang="$(language_answer)"
  run -0 --separate-stderr "$SETUP_BIN" plan "${ARGS[@]}" --answer "$lang" "$@"
  PLAN="$output"
  DIGEST="$(printf '%s\n' "$output" | sed -n 's/^digest \(sha256:[0-9a-f]\{64\}\)$/\1/p')"
  [ -n "$DIGEST" ]
  run -0 --separate-stderr "$SETUP_BIN" apply "${ARGS[@]}" --answer "$lang" "$@" --digest "$DIGEST"
}

# run_guard <script> <payload>: a guard as Claude Code runs it, from the project.
run_guard() {
  run --separate-stderr env CLAUDE_PROJECT_DIR="$PROJ" "$HOOK_BASH" "$PLUGIN/scripts/$1" <<<"$2"
}

edit_payload() {
  printf '{"tool_name":"%s","tool_input":{"file_path":"%s","old_string":"a","new_string":"b"}}' "$1" "$2"
}
