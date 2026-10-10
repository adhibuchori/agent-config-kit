#!/usr/bin/env bats
# agent-be-go's own components: the manifest, the hook wiring, the shared scripts it copies, the
# setup and sync commands, the reviewer and the two skills. Read-only checks against this repository.

load helpers

setup() {
  go_setup_env
}

@test "plugin.json: version 0.1.0, experimental, depends on agent-core, and the marketplace copies its description" {
  run jq -r '[.name, .version, (.dependencies | join(","))] | join("|")' "$PLUGIN/.claude-plugin/plugin.json"
  [ "$output" = "agent-be-go|$PLUGIN_VERSION|agent-core" ]
  [[ "$PLUGIN_VERSION" == 0.* ]] || false
  jq -r .description "$PLUGIN/.claude-plugin/plugin.json" | grep -q '^Experimental (0.x)'
  run jq -r --arg d "$(jq -r .description "$PLUGIN/.claude-plugin/plugin.json")" \
    '.plugins[] | select(.name == "agent-be-go") | [.source, (.description == $d), (has("version"))] | map(tostring) | join("|")' \
    "$KIT_ROOT/.claude-plugin/marketplace.json"
  [ "$output" = "./plugins/agent-be-go|true|false" ]
}

@test "hooks.json wires migration-guard and generated-guard on the write tools, through bash, 10 s each" {
  run jq -r '.hooks | keys | join(",")' "$PLUGIN/hooks/hooks.json"
  [ "$output" = "PreToolUse" ]
  run jq -r '.hooks.PreToolUse | length' "$PLUGIN/hooks/hooks.json"
  [ "$output" = "1" ]
  run jq -r '.hooks.PreToolUse[0].matcher' "$PLUGIN/hooks/hooks.json"
  [ "$output" = "$WRITE_MATCHER" ]
  run jq -r '.hooks.PreToolUse[0].hooks[] | [.type, .command, (.timeout | tostring)] | join("|")' "$PLUGIN/hooks/hooks.json"
  # shellcheck disable=SC2016 # the literal command strings hooks.json holds
  [ "$output" = 'command|bash "${CLAUDE_PLUGIN_ROOT}/scripts/migration-guard.sh"|10
command|bash "${CLAUDE_PLUGIN_ROOT}/scripts/generated-guard.sh"|10' ]
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

@test "the hook scripts are byte copies of the shared ones: lib.sh, migration-guard.sh, generated-guard.sh" {
  cmp "$PLUGIN/scripts/lib.sh" "$CORE/scripts/lib.sh"
  cmp "$MIGRATION_GUARD" "$KIT_ROOT/plugins/agent-be-hono/scripts/migration-guard.sh"
  cmp "$GENERATED_GUARD" "$KIT_ROOT/plugins/agent-fe-nextjs/scripts/generated-guard.sh"
}

@test "the scripts parse under bash 3.2 and download nothing" {
  local f
  for f in "$PLUGIN"/scripts/*.sh; do
    /bin/bash -n "$f"
  done
  run grep -nE '(^|[;&|]|\$\()[[:space:]]*(curl|wget|npx|bunx|uvx|pipx|pip3? install|npm install|go install)([[:space:]]|$)' \
    "$PLUGIN"/scripts/*.sh
  [ "$status" -eq 1 ]
}

@test "no component folder the plugin should not have: no bin/, no CLAUDE.md, no manifest paths" {
  [ ! -e "$PLUGIN/bin" ]
  [ ! -e "$PLUGIN/CLAUDE.md" ]
  run jq -r 'keys[]' "$PLUGIN/.claude-plugin/plugin.json"
  run ! grep -qxE 'commands|agents|skills|hooks|mcpServers|lspServers' <<<"$output"
}

@test "setup and sync call the engine with the templates path written out, for this stack" {
  local f line
  for f in setup sync; do
    while IFS= read -r line; do
      # shellcheck disable=SC2016 # the literal text of the command markdown
      [[ "$line" == *'--templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack be-go'* ]] || false
    done < <(grep -oE 'agent-(setup|sync) (questions|plan|apply|check|own) [^`]*' "$PLUGIN/commands/$f.md")
  done
  run grep -c 'agent-setup' "$PLUGIN/commands/setup.md"
  [ "$output" -gt 3 ]
  # shellcheck disable=SC2016 # a pattern, not an expansion
  run grep -n '\$CLAUDE_PLUGIN_ROOT' "$PLUGIN"/commands/*.md "$PLUGIN"/agents/*.md
  [ "$status" -eq 1 ]
  run grep -n 'hono\|drizzle\|bun ' "$PLUGIN"/commands/*.md
  [ "$status" -eq 1 ]
}

@test "setup and sync are user-only and keep every write out of their allowed tools" {
  local f tools
  for f in setup sync; do
    grep -qx 'disable-model-invocation: true' "$PLUGIN/commands/$f.md"
    tools="$(sed -n 's/^allowed-tools: //p' "$PLUGIN/commands/$f.md")"
    [ -n "$tools" ]
    [[ "$tools" != *"apply"* ]] || false
    [[ "$tools" != *"own"* ]] || false
    [[ "$tools" != *"Write"* ]] || false
    [[ "$tools" != *"Edit"* ]] || false
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

@test "setup's hand-over names the by-hand steps: module path, problem-type base, hooks path" {
  local f="$PLUGIN/commands/setup.md"
  grep -q 'example.com/service' "$f"
  grep -q 'apperr.TypeBase' "$f"
  grep -q 'git config core.hooksPath .githooks' "$f"
}

@test "the reviewer is read-only and is the standards axis" {
  local f="$PLUGIN/agents/reviewer.md"
  grep -qx 'name: reviewer' "$f"
  grep -q '^description: .*standards axis' "$f"
  run sed -n 's/^tools: //p' "$f"
  [ "$output" = "Read, Grep, Glob, Bash" ]
}

@test "each skill names its triggers and non-triggers, and keeps paths out of SKILL.md" {
  local d
  for d in api-endpoint db-migration; do
    grep -qx "name: $d" "$PLUGIN/skills/$d/SKILL.md"
    grep -q '^description: .*Use when .*Not for' "$PLUGIN/skills/$d/SKILL.md"
    [ -f "$PLUGIN/skills/$d/references/steps.md" ]
    # Every step ends on its done line.
    [ "$(grep -c 'Done when' "$PLUGIN/skills/$d/SKILL.md")" -ge 4 ]
    # A path or command in SKILL.md reads as an unresolved reference to SkillSpector; they live in
    # references/steps.md.
    run grep -nE '`[^`]*(/|\.go|\.sql|\.yaml)[^`]*`' "$PLUGIN/skills/$d/SKILL.md"
    [ "$status" -eq 1 ]
    run grep -q 'disable-model-invocation' "$PLUGIN/skills/$d/SKILL.md"
    [ "$status" -eq 1 ]
  done
}

@test "the commands, agent and skills hold no HTML comment" {
  run grep -rn '<!--' "$PLUGIN/commands" "$PLUGIN/agents" "$PLUGIN/skills"
  [ "$status" -eq 1 ]
}
