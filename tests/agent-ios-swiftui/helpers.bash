# Helpers for the agent-ios-swiftui tests. Every test builds its own temp repo under
# $BATS_TEST_TMPDIR from tests/fixtures/ios-swiftui and the plugin's template, needs no network,
# and never writes inside this repository. Xcode's tools (swift, xcrun, xcodebuild, plutil) are
# replaced by stubs where a test needs them, so the suite runs on Linux; the one check that needs
# the real plutil skips there and says why.
# shellcheck shell=bash
# The .bats files that load this read its variables, and bats's `run` sets output and status.
# shellcheck disable=SC2034,SC2154

bats_require_minimum_version 1.5.0

KIT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
PLUGIN="$KIT_ROOT/plugins/agent-ios-swiftui"
TPL="$PLUGIN/templates/ios-swiftui"
CORE="$KIT_ROOT/plugins/agent-core"
CORE_TPL="$CORE/templates/common"
GUARD="$PLUGIN/scripts/generated-guard.sh"
FIXTURES="$KIT_ROOT/tests/fixtures/ios-swiftui"
PLUGIN_VERSION="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "$PLUGIN/.claude-plugin/plugin.json")"
WRITE_MATCHER='Write|Edit|MultiEdit|mcp__serena__(replace_content|replace_symbol_body|insert_after_symbol|insert_before_symbol|replace_in_files|rename_symbol|safe_delete_symbol)'
SETUP_BIN="$CORE/bin/agent-setup"
SYNC_BIN="$CORE/bin/agent-sync"

# A clean environment for every test: no plugin root, no workspace, git config in the temp dir.
ios_setup_env() {
  unset CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA CLAUDE_PROJECT_DIR AGENT_WORKSPACE_ROOT
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  export TMPDIR="$BATS_TEST_TMPDIR"
  export PYTHONDONTWRITEBYTECODE=1
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"
  export GIT_CONFIG_NOSYSTEM=1
  printf '[user]\n\temail = test@example.invalid\n\tname = test\n[init]\n\tdefaultBranch = main\n[commit]\n\tgpgsign = false\n' \
    >"$GIT_CONFIG_GLOBAL"
  STUBS="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUBS"
}

# make_app: the probe app with this plugin's check scripts and seeds, committed; sets REPO. The seeds
# come from the template, so a change there is what the checks are tested against.
make_app() {
  REPO="$BATS_TEST_TMPDIR/app"
  mkdir -p "$REPO"
  cp -R "$FIXTURES/app/." "$REPO/"
  mkdir -p "$REPO/scripts" "$REPO/Packages/AppCore/Sources/APIClient" "$REPO/Packages/AppCore/Tests/APIClientTests"
  cp -R "$TPL/scripts/." "$REPO/scripts/"
  cp -R "$TPL/Config" "$REPO/"
  cp "$TPL/App/PrivacyInfo.xcprivacy" "$REPO/App/"
  cp "$TPL/.swiftlint.yml" "$REPO/"
  cp "$TPL/Packages/AppCore/Package.swift.starter" "$REPO/Packages/AppCore/Package.swift"
  cp "$TPL/Packages/AppCore/Sources/APIClient/AppProblem.swift" "$TPL/Packages/AppCore/Sources/APIClient/openapi-generator-config.yaml" \
    "$REPO/Packages/AppCore/Sources/APIClient/"
  cp "$TPL/Packages/AppCore/Tests/APIClientTests/AppProblemTests.swift" "$REPO/Packages/AppCore/Tests/APIClientTests/"
  git -C "$REPO" init -q
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m init
  REPO="$(cd "$REPO" && pwd -P)"
}

commit_all() { git -C "$REPO" add -A && git -C "$REPO" commit -q -m "${1:-change}"; }

# stub <name>: an executable on $STUBS that runs the script read from stdin.
stub() {
  {
    printf '#!/usr/bin/env bash\n'
    cat
  } >"$STUBS/$1"
  chmod +x "$STUBS/$1"
}

# in_repo <command...>: the command from the repo, with the stubs first on PATH.
in_repo() {
  # shellcheck disable=SC2016 # $1 and $@ expand in the child shell
  run --separate-stderr env PATH="$STUBS:$PATH" bash -c 'cd "$1" && shift && "$@"' _ "$REPO" "$@"
}

# The tool call Claude Code would send.
tool_json() { # $1 tool name, $2 JSON object of tool_input
  python3 -c 'import json, sys; print(json.dumps({"session_id": "bats", "hook_event_name": "PreToolUse", "tool_name": sys.argv[1], "tool_input": json.loads(sys.argv[2])}))' "$1" "$2"
}

# Runs the guard as the plugin runs it (CLAUDE_PLUGIN_ROOT set) with the payload on stdin.
guard_plugin() { # $1 project, $2 payload
  printf '%s' "$2" | env CLAUDE_PLUGIN_ROOT="$PLUGIN" CLAUDE_PLUGIN_DATA="$BATS_TEST_TMPDIR/data" \
    CLAUDE_PROJECT_DIR="$1" AGENT_HOOK_STATE_DIR="$BATS_TEST_TMPDIR/state" /bin/bash "$GUARD"
}

ios_engine() {
  [ -x "$SETUP_BIN" ] && [ -x "$SYNC_BIN" ] && [ -f "$CORE/libexec/agentkit.py" ]
}

# ios_setup [--answer id=value ...]: plan with these answers, then apply exactly that draft, as the
# setup command does on "go". Uses $PROJ; leaves the plan in $PLAN.
ios_setup() {
  ARGS=(--templates "$PLUGIN/templates" --stack ios-swiftui --project "$PROJ")
  run -0 --separate-stderr "$SETUP_BIN" plan "${ARGS[@]}" "$@"
  PLAN="$output"
  DIGEST="$(printf '%s\n' "$output" | sed -n 's/^digest \(sha256:[0-9a-f]\{64\}\)$/\1/p')"
  [ -n "$DIGEST" ]
  run -0 --separate-stderr "$SETUP_BIN" apply "${ARGS[@]}" "$@" --digest "$DIGEST"
}
