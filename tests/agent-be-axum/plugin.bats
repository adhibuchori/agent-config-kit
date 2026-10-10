#!/usr/bin/env bats
# agent-be-axum's own components: the hook wiring, the scripts it ships, the setup and sync
# commands, the reviewer subagent and the two skills. Read-only checks against this repository.

# shellcheck disable=SC2016 # Markdown and hook text, quoted as written
load helpers

setup() {
  ax_setup_env
}

@test "hooks.json wires migration-guard and generated-guard on the write tools, through bash with 10 s" {
  run jq -r '.hooks | keys | join(",")' "$PLUGIN/hooks/hooks.json"
  [ "$output" = "PreToolUse" ]
  run jq -r '.hooks.PreToolUse | length' "$PLUGIN/hooks/hooks.json"
  [ "$output" = "1" ]
  run jq -r '.hooks.PreToolUse[0].matcher' "$PLUGIN/hooks/hooks.json"
  [ "$output" = "$WRITE_MATCHER" ]
  run jq -r '.hooks.PreToolUse[0].hooks[] | [.type, .command, (.timeout | tostring)] | join("|")' "$PLUGIN/hooks/hooks.json"
  # shellcheck disable=SC2016 # the literal command strings hooks.json holds
  [ "${lines[0]}" = 'command|bash "${CLAUDE_PLUGIN_ROOT}/scripts/migration-guard.sh"|10' ]
  # shellcheck disable=SC2016
  [ "${lines[1]}" = 'command|bash "${CLAUDE_PLUGIN_ROOT}/scripts/generated-guard.sh"|10' ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "every script the hooks run exists, is executable, and sits next to lib.sh" {
  local cmd script
  while IFS= read -r cmd; do
    script="${cmd#bash \"\$\{CLAUDE_PLUGIN_ROOT\}/}"
    script="${script%\"}"
    [ -x "$PLUGIN/$script" ]
  done < <(jq -r '.. | objects | select(has("command")) | .command' "$PLUGIN/hooks/hooks.json")
  [ -x "$PLUGIN/scripts/lib.sh" ]
}

@test "the scripts are the shared copies, byte for byte" {
  cmp "$PLUGIN/scripts/lib.sh" "$CORE/scripts/lib.sh"
  cmp "$PLUGIN/scripts/migration-guard.sh" "$KIT_ROOT/plugins/agent-be-hono/scripts/migration-guard.sh"
  cmp "$PLUGIN/scripts/generated-guard.sh" "$KIT_ROOT/plugins/agent-fe-nextjs/scripts/generated-guard.sh"
}

@test "the scripts parse under bash 3.2 and download nothing" {
  local f
  for f in "$PLUGIN"/scripts/*.sh "$TPL"/scripts/check/*.sh "$TPL/.githooks/pre-commit"; do
    /bin/bash -n "$f"
  done
  run grep -nE '(^|[;&|]|\$\()[[:space:]]*(curl|wget|npx|bunx|uvx|pipx|pip3? install|npm install|cargo install)([[:space:]]|$)' \
    "$PLUGIN"/scripts/migration-guard.sh "$PLUGIN"/scripts/generated-guard.sh "$TPL"/scripts/check/*.sh
  [ "$status" -eq 1 ]
}

@test "no component folder the plugin should not have, and agent-core is its only dependency" {
  [ ! -e "$PLUGIN/bin" ]
  [ ! -e "$PLUGIN/CLAUDE.md" ]
  run jq -r 'keys[]' "$PLUGIN/.claude-plugin/plugin.json"
  run ! grep -qxE 'commands|agents|skills|hooks|mcpServers|lspServers' <<<"$output"
  run jq -r '(.dependencies | join(",")), .version, (.description | test("^Experimental"))' "$PLUGIN/.claude-plugin/plugin.json"
  [ "${lines[0]}" = "agent-core" ]
  [ "${lines[1]}" = "0.1.0" ]
  [ "${lines[2]}" = "true" ]
}

@test "setup and sync call the engine with the templates path written out, for this stack" {
  local f line
  for f in setup sync; do
    while IFS= read -r line; do
      # shellcheck disable=SC2016 # the literal text of the command markdown
      [[ "$line" == *'--templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack be-axum'* ]] || false
    done < <(grep -oE 'agent-(setup|sync) (questions|plan|apply|check|own) [^`]*' "$PLUGIN/commands/$f.md")
  done
  # shellcheck disable=SC2016 # a pattern, not an expansion
  run grep -n '\$CLAUDE_PLUGIN_ROOT' "$PLUGIN"/commands/*.md "$PLUGIN"/agents/*.md
  [ "$status" -eq 1 ]
}

@test "setup and sync are user-only and keep every write out of their allowed tools" {
  local f tools
  for f in setup sync; do
    grep -qx 'disable-model-invocation: true' "$PLUGIN/commands/$f.md"
    tools="$(sed -n 's/^allowed-tools: //p' "$PLUGIN/commands/$f.md")"
    [ -n "$tools" ]
    [[ "$tools" != *"apply"* && "$tools" != *"own"* && "$tools" != *"Write"* && "$tools" != *"Edit"* ]] || false
  done
}

@test "setup follows explore, ask, draft, write on go, verify, in that order" {
  run grep -nE '^## [0-9]\.' "$PLUGIN/commands/setup.md"
  [[ "${lines[0]}" == *"## 0. Check the engine"* ]] || false
  [[ "${lines[1]}" == *"## 1. Explore (read-only)"* ]] || false
  [[ "${lines[2]}" == *"## 2. Ask, one question at a time"* ]] || false
  [[ "${lines[3]}" == *"## 3. Draft"* ]] || false
  [[ "${lines[4]}" == *'## 4. Write only on "go"'* ]] || false
  [[ "${lines[5]}" == *"## 5. Verify and hand over"* ]] || false
}

@test "the reviewer is read-only and named as the stack reviewer" {
  local f="$PLUGIN/agents/reviewer.md"
  grep -qx 'name: reviewer' "$f"
  run sed -n 's/^tools: //p' "$f"
  [ "$output" = "Read, Grep, Glob, Bash" ]
}

@test "each skill names its triggers and non-triggers, ends every step on a done line, and keeps paths in references" {
  local skill f
  for skill in api-endpoint db-migration; do
    f="$PLUGIN/skills/$skill/SKILL.md"
    grep -qx "name: $skill" "$f"
    grep -q '^description: .*Use when .*Not for ' "$f"
    [ -f "$PLUGIN/skills/$skill/references/steps.md" ]
    [ "$(grep -cE '^[0-9]+\. \*\*' "$f")" -eq "$(grep -c 'Done when' "$f")" ]
    # SkillSpector reads `a/b` tokens and file names in SKILL.md as references it must resolve.
    run grep -nE '`[^`]*(/|\.(rs|sql|toml|json|sh))[^`]*`' "$f"
    [ "$status" -eq 1 ]
  done
}
