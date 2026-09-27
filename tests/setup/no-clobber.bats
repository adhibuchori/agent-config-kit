#!/usr/bin/env bats
# shellcheck disable=SC2016 # single-quoted JSON holds a literal $CLAUDE_PROJECT_DIR
# Setup never overwrites or deletes: an existing file is kept, and the only edits to files that
# already exist are the four managed merges (.claude/settings.json, one .gitignore block, one
# CLAUDE.md block, a missing package.json script), each shown in the draft first.

load ../helpers/common

setup() {
  kit_isolate "$BATS_TEST_TMPDIR/env"
  P="$BATS_TEST_TMPDIR/proj"
  new_repo "$P"
  core_args "$P"
}

@test "an existing file with other bytes is kept untouched, listed as keep, and never counted as drift" {
  mkdir -p "$P/scripts/ops" && printf '#!/bin/sh\necho mine\n' >"$P/scripts/ops/unlock.sh"
  run -0 --separate-stderr setup_cli plan "${ARGS[@]}"
  [[ "$output" == *"  keep     scripts/ops/unlock.sh"*"(exists; left alone; compare with agent-core templates/common/scripts/ops/unlock.sh)"* ]]
  setup_now
  [ "$(cat "$P/scripts/ops/unlock.sh")" = "$(printf '#!/bin/sh\necho mine')" ]
  [ "$(json_q "$P/.claude/agent-config-kit.lock" 'd["plugins"]["agent-core"]["kept"]')" = '["scripts/ops/unlock.sh"]' ]
  run -0 --separate-stderr sync_cli check "${ARGS[@]}"
  [[ "$output" == *"kept  scripts/ops/unlock.sh  existed before setup; left alone"* ]]
}

@test "an existing file with the template's bytes is managed (same), not rewritten" {
  mkdir -p "$P/docs" && cp "$COMMON/docs/unlock.md" "$P/docs/unlock.md"
  touch -t 202001010000 "$P/docs/unlock.md"
  run -0 --separate-stderr setup_cli plan "${ARGS[@]}"
  [[ "$output" == *"  same     docs/unlock.md"*"(already identical; managed)"* ]]
  setup_now
  [ "$(json_q "$P/.claude/agent-config-kit.lock" '"docs/unlock.md" in d["plugins"]["agent-core"]["files"]')" = true ]
  # Not rewritten: the modification time is the one set before setup.
  [ -z "$(find "$P/docs/unlock.md" -newer "$P/.git/HEAD")" ]
}

@test "a seed file the project already has is kept, and later checks stay in sync" {
  printf '{"mcpServers": {}}\n' >"$P/.mcp.json"
  setup_now
  [ "$(cat "$P/.mcp.json")" = '{"mcpServers": {}}' ]
  run -0 --separate-stderr sync_cli check "${ARGS[@]}"
  [[ "$output" == *"kept  .mcp.json  existed before setup; left alone"* ]]
  [[ "$output" != *"new  .mcp.json"* ]]
}

@test "CLAUDE.md without markers keeps every byte and gains the block after one blank line" {
  printf '# My project\n\nHouse rules.' >"$P/CLAUDE.md"
  original="$(cat "$P/CLAUDE.md")"
  setup_now
  python3 - "$P/CLAUDE.md" "$COMMON/_kit/claude-md.md" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
fragment = open(sys.argv[2], encoding="utf-8").read().strip("\n")
head = "# My project\n\nHouse rules.\n\n"
assert text.startswith(head + "<!-- >>> agent-config-kit: managed by /agent-core:setup and sync"), repr(text[:120])
assert "\n## Agent config kit\n" in text and fragment in text
assert text.endswith("<!-- <<< agent-config-kit -->\n")
assert text.count("<!-- >>> agent-config-kit") == 1
PY
  [ "$(head -3 "$P/CLAUDE.md")" = "$original" ]
  run -0 --separate-stderr sync_cli check "${ARGS[@]}"
}

@test "CLAUDE.md's text outside the block survives a sync that updates the block" {
  printf '# Mine\n' >"$P/CLAUDE.md"
  setup_now
  printf '\n## Added after setup\n\nMore of mine.\n' >>"$P/CLAUDE.md"
  run -0 --separate-stderr sync_cli check "${ARGS[@]}"
  sync_now
  [ "$(head -1 "$P/CLAUDE.md")" = "# Mine" ]
  [ "$(tail -1 "$P/CLAUDE.md")" = "More of mine." ]
}

@test "CLAUDE.md with repeated block markers is a conflict and is left alone" {
  printf '<!-- <<< agent-config-kit -->\n# Mine\n<!-- <<< agent-config-kit -->\n' >"$P/CLAUDE.md"
  before="$(cat "$P/CLAUDE.md")"
  run -0 --separate-stderr setup_cli plan "${ARGS[@]}"
  [[ "$output" == *"  conflict CLAUDE.md"*"block markers repeated or out of order"* ]]
  setup_now
  [ "$(cat "$P/CLAUDE.md")" = "$before" ]
}

@test "a .gitignore without a trailing newline keeps its lines and gains the managed block" {
  printf 'node_modules\n.env' >"$P/.gitignore"
  setup_now
  [ "$(cat "$P/.gitignore")" = "$(printf 'node_modules\n.env\n\n# >>> agent-config-kit (managed by /agent-core:setup and sync; edit outside this block)\n.claude/state/\n.claude/settings.local.json\n.claude/session-logs/\n# <<< agent-config-kit')" ]
  git -C "$P" check-ignore -q .claude/state/unlock/env
  git -C "$P" check-ignore -q .claude/settings.local.json
}

@test "settings.json merges additively: user entries, order and keys kept; a differing scalar is a kept conflict" {
  mkdir -p "$P/.claude"
  cat >"$P/.claude/settings.json" <<'EOF'
{
  "model": "custom",
  "permissions": {"allow": ["Bash(npm test:*)", "Read(**)"], "deny": ["Bash(curl:*)"]},
  "sandbox": {"enabled": false}
}
EOF
  run -0 --separate-stderr setup_cli plan "${ARGS[@]}"
  [[ "$output" == *"  merge    .claude/settings.json"* ]]
  [[ "$output" == *"  conflict .claude/settings.json /sandbox/enabled  yours: false, kit: true (kept yours)"* ]]
  setup_now
  python3 - "$P/.claude/settings.json" "$COMMON/.claude/settings.json" <<'PY'
import json, sys
mine = json.load(open(sys.argv[1]))
kit = json.load(open(sys.argv[2]))
assert list(mine)[:3] == ["model", "permissions", "sandbox"], list(mine)
assert mine["model"] == "custom" and mine["sandbox"]["enabled"] is False
allow = mine["permissions"]["allow"]
assert allow[:2] == ["Bash(npm test:*)", "Read(**)"] and allow.count("Read(**)") == 1, allow
assert mine["permissions"]["deny"][0] == "Bash(curl:*)"
for key in ("allow", "ask", "deny"):
    assert set(kit["permissions"][key]) <= set(mine["permissions"][key]), key
assert mine["sandbox"]["filesystem"] == kit["sandbox"]["filesystem"]
assert "hooks" not in mine
PY
  # The kept conflict is not recorded, so it is never reported as missing.
  [ "$(json_q "$P/.claude/agent-config-kit.lock" '"/sandbox/enabled" in d["plugins"]["agent-core"]["settings"]')" = false ]
  run -0 --separate-stderr sync_cli check "${ARGS[@]}"
}

@test "a settings.json that is not JSON is a conflict: nothing written to it, the entries shown to add by hand" {
  mkdir -p "$P/.claude" && printf '{ not json\n' >"$P/.claude/settings.json"
  run -0 --separate-stderr setup_cli plan "${ARGS[@]}"
  [[ "$output" == *"  conflict .claude/settings.json"*"is not valid JSON: nothing written; add by hand: {"* ]]
  setup_now
  [ "$(cat "$P/.claude/settings.json")" = "{ not json" ]
}

@test "hook wiring in the project's settings is never edited: the draft warns about double wiring" {
  mkdir -p "$P/.claude"
  cat >"$P/.claude/settings.json" <<'EOF'
{"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/safety-check.sh\""}]}]}}
EOF
  run -0 --separate-stderr setup_cli plan "${ARGS[@]}"
  [[ "$output" == *"  warn     .claude/settings.json"*"hooks.PreToolUse[0] runs safety-check.sh, which agent-core also runs"* ]]
  setup_now
  [ "$(json_q "$P/.claude/settings.json" 'd["hooks"]')" = '{"PreToolUse": [{"hooks": [{"command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/safety-check.sh\"", "type": "command"}], "matcher": "Bash"}]}' ]
}

@test "no package.json: none is created, and the draft says how unlock runs instead" {
  run -0 --separate-stderr setup_cli plan "${ARGS[@]}"
  [[ "$output" == *"  note     package.json"*"none here, so no unlock script is added; unlock runs as ./scripts/ops/unlock.sh"* ]]
  setup_now
  [ ! -e "$P/package.json" ]
  [ "$(json_q "$P/.claude/agent-config-kit.lock" 'd["plugins"]["agent-core"]["packageScripts"]')" = '{}' ]
}

@test "package.json gains only the unlock script, keeping its indentation, key order and trailing newline" {
  printf '{\n    "name": "app",\n    "private": true,\n    "scripts": {\n        "build": "tsc"\n    },\n    "devDependencies": {}\n}\n' >"$P/package.json"
  run -0 --separate-stderr setup_cli plan "${ARGS[@]}"
  [[ "$output" == *'  alias    package.json                            scripts.unlock = "bash scripts/ops/unlock.sh"'* ]]
  setup_now
  [ "$(cat "$P/package.json")" = "$(printf '{\n    "name": "app",\n    "private": true,\n    "scripts": {\n        "build": "tsc",\n        "unlock": "bash scripts/ops/unlock.sh"\n    },\n    "devDependencies": {}\n}')" ]
  [ "$(tail -c 1 "$P/package.json" | od -An -c | tr -d ' ')" = '\n' ]
  [ "$(json_q "$P/.claude/agent-config-kit.lock" 'd["plugins"]["agent-core"]["packageScripts"]')" = '{"unlock": "bash scripts/ops/unlock.sh"}' ]
}

@test "package.json without scripts, or written on one line, is edited in its own style" {
  printf '{\n  "name": "app"\n}\n' >"$P/package.json"
  setup_now
  [ "$(cat "$P/package.json")" = "$(printf '{\n  "name": "app",\n  "scripts": {\n    "unlock": "bash scripts/ops/unlock.sh"\n  }\n}')" ]
  Q="$BATS_TEST_TMPDIR/one-line" && new_repo "$Q" && core_args "$Q"
  printf '{"name":"app","scripts":{}}\n' >"$Q/package.json"
  setup_now
  [ "$(cat "$Q/package.json")" = '{"name":"app","scripts":{"unlock": "bash scripts/ops/unlock.sh"}}' ]
}

@test "an unlock script with another value is a kept conflict and is not recorded" {
  printf '{"scripts": {"unlock": "node my-unlock.js"}}\n' >"$P/package.json"
  run -0 --separate-stderr setup_cli plan "${ARGS[@]}"
  [[ "$output" == *'  conflict package.json scripts.unlock'*'yours: "node my-unlock.js", kit: "bash scripts/ops/unlock.sh" (kept yours)'* ]]
  setup_now
  [ "$(cat "$P/package.json")" = '{"scripts": {"unlock": "node my-unlock.js"}}' ]
  [ "$(json_q "$P/.claude/agent-config-kit.lock" 'd["plugins"]["agent-core"]["packageScripts"]')" = '{}' ]
  run -0 --separate-stderr sync_cli check "${ARGS[@]}"
}

@test "a package.json that is not a JSON object is a conflict and is left alone" {
  printf '[1, 2]\n' >"$P/package.json"
  run -0 --separate-stderr setup_cli plan "${ARGS[@]}"
  [[ "$output" == *"  conflict package.json"*"not a JSON object with a scripts object: add by hand: scripts.unlock"* ]]
  setup_now
  [ "$(cat "$P/package.json")" = "[1, 2]" ]
}

@test "files the project had before setup keep every byte and mode, the four merges aside" {
  mkdir -p "$P/src" "$P/.claude/rules/common" "$P/scripts/check"
  echo 'export const x = 1' >"$P/src/index.ts"
  echo 'my rule' >"$P/.claude/rules/common/working-agreements.md"
  printf '#!/bin/sh\n' >"$P/scripts/check/gates.sh" && chmod 644 "$P/scripts/check/gates.sh"
  echo 'x' >"$P/README.md"
  mine=(src/index.ts .claude/rules/common/working-agreements.md scripts/check/gates.sh README.md)
  before="$(for f in "${mine[@]}"; do printf '%s %s %s\n' "$f" "$(sha_of "$P/$f")" "$(mode_of "$P/$f")"; done)"
  setup_now
  after="$(for f in "${mine[@]}"; do printf '%s %s %s\n' "$f" "$(sha_of "$P/$f")" "$(mode_of "$P/$f")"; done)"
  [ "$after" = "$before" ]
  [ "$(json_q "$P/.claude/agent-config-kit.lock" 'd["plugins"]["agent-core"]["kept"] + d["plugins"]["agent-core"]["seeded"]')" = '[".claude/rules/common/working-agreements.md", "scripts/check/gates.sh", ".gitleaks.toml", ".mcp.json", ".skillspector-baseline.yaml"]' ]
}
