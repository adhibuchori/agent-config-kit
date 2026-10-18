#!/usr/bin/env bats
# agent-ios-swiftui's own components: the hook wiring, the scripts it ships, the setup and sync
# commands, a11y-audit, the two subagents and the two skills. Read-only checks against this
# repository.

load helpers

setup() {
  ios_setup_env
}

@test "the manifest: stable (1.x or later, not marked experimental), depends on agent-core, no component paths" {
  run jq -r '.version' "$PLUGIN/.claude-plugin/plugin.json"
  [[ "$output" != 0.* ]] || false
  run jq -r '.description' "$PLUGIN/.claude-plugin/plugin.json"
  [[ "$output" != *xperimental* ]] || false
  run jq -r '.dependencies | join(",")' "$PLUGIN/.claude-plugin/plugin.json"
  [ "$output" = "agent-core" ]
  run jq -r 'keys[]' "$PLUGIN/.claude-plugin/plugin.json"
  run ! grep -qxE 'commands|agents|skills|hooks|mcpServers|lspServers' <<<"$output"
  [ ! -e "$PLUGIN/bin" ]
  [ ! -e "$PLUGIN/CLAUDE.md" ]
}

@test "hooks.json wires generated-guard once, on the write tools, through bash with a 10 s timeout" {
  run jq -r '.hooks | keys | join(",")' "$PLUGIN/hooks/hooks.json"
  [ "$output" = "PreToolUse" ]
  run jq -r '.hooks.PreToolUse | length' "$PLUGIN/hooks/hooks.json"
  [ "$output" = "1" ]
  run jq -r '.hooks.PreToolUse[0].matcher' "$PLUGIN/hooks/hooks.json"
  [ "$output" = "$WRITE_MATCHER" ]
  run jq -r '.hooks.PreToolUse[0].hooks[] | [.type, .command, (.timeout | tostring)] | join("|")' "$PLUGIN/hooks/hooks.json"
  # shellcheck disable=SC2016 # the literal command string hooks.json holds
  [ "$output" = 'command|bash "${CLAUDE_PLUGIN_ROOT}/scripts/generated-guard.sh"|10' ]
}

@test "lib.sh and generated-guard.sh are byte copies of agent-core's and agent-fe-nextjs's" {
  cmp "$PLUGIN/scripts/lib.sh" "$CORE/scripts/lib.sh"
  [ -f "$KIT_ROOT/plugins/agent-fe-nextjs/scripts/generated-guard.sh" ] || skip "agent-fe-nextjs is not in this tree"
  cmp "$GUARD" "$KIT_ROOT/plugins/agent-fe-nextjs/scripts/generated-guard.sh"
  [ -x "$GUARD" ] && [ -x "$PLUGIN/scripts/lib.sh" ]
}

@test "the scripts parse under bash 3.2 and download nothing" {
  local f
  for f in "$PLUGIN"/scripts/*.sh "$TPL"/scripts/check/*.sh "$TPL"/scripts/ios/*.sh "$TPL/.githooks/pre-commit"; do
    /bin/bash -n "$f"
  done
  run grep -nE '(^|[;&|]|\$\()[[:space:]]*(curl|wget|npx|bunx|uvx|pipx|pip3? install|npm install|brew install|mint install)([[:space:]]|$)' \
    "$PLUGIN"/scripts/*.sh "$TPL"/scripts/check/*.sh "$TPL"/scripts/ios/*.sh
  [ "$status" -eq 1 ]
}

@test "setup and sync call the engine with the templates path written out, for this stack" {
  local f line
  for f in setup sync; do
    while IFS= read -r line; do
      # shellcheck disable=SC2016 # the literal text of the command markdown
      [[ "$line" == *'--templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack ios-swiftui'* ]] || false
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
    [[ "$tools" != *"apply"* ]] || false
    [[ "$tools" != *" own"* ]] || false
    [[ "$tools" != *"Write"* ]] || false
    [[ "$tools" != *"Edit"* ]] || false
    [[ "$tools" != *"Bash(xcodebuild:"* ]] || false
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

@test "a11y-audit reads and reports through the named script, and never signs" {
  local f="$PLUGIN/commands/a11y-audit.md"
  grep -q '^description: ' "$f"
  grep -q 'bash scripts/ios/app.sh ui-test' "$f"
  run grep -nE 'CODE_SIGN|provisioning|xcodebuild test' "$f"
  [ "$status" -eq 1 ]
}

@test "the subagents are read-only and named" {
  local name
  for name in reviewer i18n-guard; do
    grep -qx "name: $name" "$PLUGIN/agents/$name.md"
    grep -q '^description: ' "$PLUGIN/agents/$name.md"
    run sed -n 's/^tools: //p' "$PLUGIN/agents/$name.md"
    [ "$output" = "Read, Grep, Glob, Bash" ]
  done
}

@test "each skill names its triggers, ends every step on a done line, and keeps paths in references" {
  local skill f
  for skill in swiftui-screen openapi-client-update; do
    f="$PLUGIN/skills/$skill/SKILL.md"
    grep -qx "name: $skill" "$f"
    grep -qE '^description: .*Use when .*Not for' "$f"
    [ -f "$PLUGIN/skills/$skill/references/steps.md" ]
    # Every numbered step has its "Done when" line.
    [ "$(grep -cE '^[0-9]+\. \*\*' "$f")" -eq "$(grep -cE '^   Done when ' "$f")" ]
    # No repo path or file name in the skill's own prose: those live in references/steps.md.
    # shellcheck disable=SC2016 # Markdown backticks, not a command
    run grep -nE '`[^`]*/[^`]*`|`[^` ]+\.[a-z]+`' "$f"
    [ "$status" -eq 1 ]
  done
}
