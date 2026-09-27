# shellcheck shell=bash
# Helpers for tests/agent-fe-nextjs/*.bats. Every test builds its own temp repo under
# $BATS_TEST_TMPDIR; nothing here needs the network.

bats_require_minimum_version 1.5.0

# The paths below are read by the .bats files that load this helper.
# shellcheck disable=SC2034
{
  KIT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  PLUGIN="$KIT_ROOT/plugins/agent-fe-nextjs"
  TEMPLATES="$PLUGIN/templates"
  STACK_DIR="$TEMPLATES/fe-nextjs"
  CORE="$KIT_ROOT/plugins/agent-core"
  FIXTURE="$KIT_ROOT/tests/fixtures/fe-nextjs"
  GUARD="$PLUGIN/scripts/generated-guard.sh"
}

# A git repo on a work branch holding a generated API client, a hand-written client beside it, and a
# copied OpenAPI contract: the shapes generated-guard is asked about.
make_project() { # $1 dir
  local dir="$1"
  git init -q -b feature/probe "$dir"
  git -C "$dir" -c user.name=t -c user.email=t@t.invalid commit -q --allow-empty -m init
  mkdir -p "$dir/src/lib/api/generated" "$dir/src/lib/api/client" "$dir/content/generated"
  echo 'export const probeNeedle = 1;' >"$dir/src/lib/api/generated/api.ts"
  echo 'export const other = 2;' >"$dir/src/lib/api/client/mutator.ts"
  echo '{"openapi": "3.1.0"}' >"$dir/openapi.json"
  echo 'probe' >"$dir/content/generated/page.mdx"
}

opt_in_lock() { mkdir -p "$1/.claude" && echo '{}' >"$1/.claude/agent-config-kit.lock"; }
opt_in_config() { # $1 project, [$2 JSON body; default {}]
  local body='{}'
  [ "$#" -ge 2 ] && body="$2"
  mkdir -p "$1/.claude" && printf '%s\n' "$body" >"$1/.claude/agent-config.json"
}

tool_json() { # $1 tool name, $2 JSON object of tool_input
  python3 -c 'import json, sys; print(json.dumps({"session_id": "bats", "hook_event_name": "PreToolUse", "tool_name": sys.argv[1], "tool_input": json.loads(sys.argv[2])}))' "$1" "$2"
}

# Runs the guard as the plugin runs it (CLAUDE_PLUGIN_ROOT set) with the payload on stdin.
# $1 project, $2 payload, then VAR=value pairs.
guard_plugin() {
  local proj="$1" payload="$2"
  shift 2
  printf '%s' "$payload" | env CLAUDE_PLUGIN_ROOT="$PLUGIN" CLAUDE_PLUGIN_DATA="$BATS_TEST_TMPDIR/data" \
    CLAUDE_PROJECT_DIR="$proj" "$@" /bin/bash "$GUARD"
}

# The same script copied into a repo as a template: no CLAUDE_PLUGIN_ROOT, so no project gate.
guard_template() {
  local proj="$1" payload="$2"
  shift 2
  printf '%s' "$payload" | env -u CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR="$proj" \
    AGENT_HOOK_STATE_DIR="$BATS_TEST_TMPDIR/state" "$@" /bin/bash "$GUARD"
}

# PATH folders holding only what the hooks may call: nopy has jq but no python3, nojq python3 but
# no jq, nojson neither.
make_kits() {
  local kit tool p
  for kit in nopy nojq nojson; do
    mkdir -p "$BATS_TEST_TMPDIR/$kit"
    for tool in bash cat dirname basename sed paste grep awk tr sort comm head sleep git env mkdir rm touch jq python3; do
      case "$kit:$tool" in nopy:python3 | nojq:jq | nojson:jq | nojson:python3) continue ;; esac
      p="$(command -v "$tool" 2>/dev/null)" && ln -sf "$p" "$BATS_TEST_TMPDIR/$kit/$tool"
    done
  done
}
