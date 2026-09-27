#!/usr/bin/env bats
# agent-ai-fastapi's own components: the hook wiring, the scripts it ships, the setup and sync
# commands, and the ai-reviewer subagent. Read-only checks against this repository.

load helpers

setup() {
  ai_setup_env
}

@test "hooks.json wires migration-guard once, on the write tools, through bash with a 10 s timeout" {
  run jq -r '.hooks | keys | join(",")' "$PLUGIN/hooks/hooks.json"
  [ "$output" = "PreToolUse" ]
  run jq -r '.hooks.PreToolUse | length' "$PLUGIN/hooks/hooks.json"
  [ "$output" = "1" ]
  run jq -r '.hooks.PreToolUse[0].matcher' "$PLUGIN/hooks/hooks.json"
  [ "$output" = "$WRITE_MATCHER" ]
  run jq -r '.hooks.PreToolUse[0].hooks[] | [.type, .command, (.timeout | tostring), (.timeout | type)] | join("|")' \
    "$PLUGIN/hooks/hooks.json"
  # shellcheck disable=SC2016 # the literal command string hooks.json holds
  [ "$output" = 'command|bash "${CLAUDE_PLUGIN_ROOT}/scripts/migration-guard.sh"|10|number' ]
}

@test "the matcher covers every write tool and nothing that only reads" {
  local tool
  for tool in Write Edit MultiEdit mcp__serena__replace_content mcp__serena__replace_symbol_body \
    mcp__serena__insert_after_symbol mcp__serena__insert_before_symbol mcp__serena__replace_in_files \
    mcp__serena__rename_symbol mcp__serena__safe_delete_symbol; do
    [[ "$tool" =~ ^($WRITE_MATCHER)$ ]] || false
  done
  for tool in Bash Read Glob Grep mcp__serena__find_symbol mcp__db-prod__execute_sql; do
    if [[ "$tool" =~ ^($WRITE_MATCHER)$ ]]; then
      echo "the matcher takes a read-only tool: $tool" >&2
      return 1
    fi
  done
}

@test "every script the hooks run exists, is executable, and sits next to lib.sh" {
  local cmd script
  while IFS= read -r cmd; do
    script="${cmd#bash \"\$\{CLAUDE_PLUGIN_ROOT\}/}"
    script="${script%\"}"
    [ -f "$PLUGIN/$script" ]
    [ -x "$PLUGIN/$script" ]
  done < <(jq -r '.. | objects | select(has("command")) | .command' "$PLUGIN/hooks/hooks.json")
  [ -x "$PLUGIN/scripts/lib.sh" ]
}

@test "scripts/lib.sh is the same bytes as agent-core's" {
  [ -f "$CORE/scripts/lib.sh" ] || skip "agent-core has no scripts/lib.sh yet"
  cmp "$PLUGIN/scripts/lib.sh" "$CORE/scripts/lib.sh"
}

@test "migration-guard.sh is the same bytes as agent-be-hono's, so both stacks guard alike" {
  [ -f "$KIT_ROOT/plugins/agent-be-hono/scripts/migration-guard.sh" ] || skip "agent-be-hono not built"
  cmp "$PLUGIN/scripts/migration-guard.sh" "$KIT_ROOT/plugins/agent-be-hono/scripts/migration-guard.sh"
}

@test "the scripts parse under bash 3.2 and download nothing" {
  local f
  for f in "$PLUGIN"/scripts/*.sh; do
    /bin/bash -n "$f"
  done
  # A downloader or package runner in command position, on a line that is not a comment. lib.sh
  # names them as data (the command analyzer unwraps npx and bunx), which is not a call.
  run grep -nE '(^|[;&|]|\$\()[[:space:]]*(curl|wget|npx|bunx|uvx|pipx|pip3? install|npm install)([[:space:]]|$)' \
    "$PLUGIN"/scripts/*.sh
  [ "$status" -eq 1 ]
  # migration-guard.sh, this plugin's own script, does not even mention one.
  run grep -nE '\b(curl|wget|npx|bunx|uvx|pipx)\b|pip install|npm install' "$GUARD"
  [ "$status" -eq 1 ]
}

@test "no component folder the plugin should not have: no bin/, no CLAUDE.md, no manifest paths" {
  [ ! -e "$PLUGIN/bin" ]
  [ ! -e "$PLUGIN/CLAUDE.md" ]
  run jq -r 'keys[]' "$PLUGIN/.claude-plugin/plugin.json"
  run ! grep -qxE 'commands|agents|skills|hooks|mcpServers|lspServers' <<<"$output"
  run jq -r '.dependencies | join(",")' "$PLUGIN/.claude-plugin/plugin.json"
  [ "$output" = "agent-core" ]
}

@test "setup and sync call the engine with the templates path written out, for this stack" {
  local f line
  for f in setup sync; do
    while IFS= read -r line; do
      # shellcheck disable=SC2016 # the literal text of the command markdown
      [[ "$line" == *'--templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack ai-fastapi'* ]] || false
    done < <(grep -oE 'agent-(setup|sync) (questions|plan|apply|check|own) [^`]*' "$PLUGIN/commands/$f.md")
  done
  run grep -c 'agent-setup' "$PLUGIN/commands/setup.md"
  [ "$output" -gt 3 ]
  # Never the unbraced form, which the Bash tool would leave empty.
  # shellcheck disable=SC2016 # a pattern, not an expansion
  run grep -n '\$CLAUDE_PLUGIN_ROOT' "$PLUGIN"/commands/*.md "$PLUGIN"/agents/*.md
  [ "$status" -eq 1 ]
}

@test "setup and sync keep every write out of their allowed tools" {
  local f tools
  for f in setup sync; do
    tools="$(sed -n 's/^allowed-tools: //p' "$PLUGIN/commands/$f.md")"
    [ -n "$tools" ]
    [[ "$tools" != *"apply"* ]] || false
    [[ "$tools" != *"own"* ]] || false
    [[ "$tools" != *"Write"* ]] || false
    [[ "$tools" != *"Edit"* ]] || false
  done
  grep -q '^description: ' "$PLUGIN/commands/setup.md"
  grep -q '^argument-hint: ' "$PLUGIN/commands/setup.md"
  grep -q '^description: ' "$PLUGIN/commands/sync.md"
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

@test "ai-reviewer is read-only and named as the stack reviewer" {
  local f="$PLUGIN/agents/ai-reviewer.md"
  grep -qx 'name: ai-reviewer' "$f"
  grep -q '^description: ' "$f"
  run sed -n 's/^tools: //p' "$f"
  [ "$output" = "Read, Grep, Glob, Bash" ]
}

@test "ai-reviewer's pipeline checks are the pipeline example's Review additions, word for word" {
  local readme="$TPL/.claude/examples/pipeline/README.md" want got
  want="$(sed -n '/^## Review additions$/,$p' "$readme" | sed '1,2d')"
  got="$(sed -n '/^### Pipeline shape/,/^## Output$/p' "$PLUGIN/agents/ai-reviewer.md" | sed '1,5d' | sed '$d' | sed '$d')"
  [ "$(grep -c '^- ' <<<"$want")" -ge 10 ]
  [ "$want" = "$got" ]
}
