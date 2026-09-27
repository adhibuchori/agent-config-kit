#!/usr/bin/env bats
# What a new plugin version means for a project that was set up with an older one, and how a stack
# plugin's setup layers on agent-core's. Each test changes its own copy of agent-core (ENGINE_CORE),
# never the checkout.

load ../helpers/common

setup() {
  kit_isolate "$BATS_TEST_TMPDIR/env"
  P="$BATS_TEST_TMPDIR/proj"
  new_repo "$P"
  ENGINE_CORE="$(copy_core "$BATS_TEST_TMPDIR/kit")"
  K="$ENGINE_CORE"
  core_args "$P"
}

# $1 new version: rewrites the copy's plugin.json.
bump() {
  python3 - "$K/.claude-plugin/plugin.json" "$1" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["version"] = sys.argv[2]
open(sys.argv[1], "w").write(json.dumps(d, indent=2) + "\n")
PY
}

@test "a new plugin version is version drift (exit 1) until sync records it" {
  setup_now
  bump 1.1.0
  run -1 --separate-stderr sync_cli check "${ARGS[@]}"
  [[ "$output" == *"version  .claude/agent-config-kit.lock  agent-core: set up with $CORE_VERSION, 1.1.0 installed"* ]]
  sync_now
  [ "$(json_q "$P/.claude/agent-config-kit.lock" 'd["plugins"]["agent-core"]["version"]')" = 1.1.0 ]
  run -0 --separate-stderr sync_cli check "${ARGS[@]}"
}

@test "a template that changed upstream is stale while the project copy is untouched; sync replaces it" {
  setup_now
  echo 'A new paragraph.' >>"$K/templates/common/docs/unlock.md"
  run -1 --separate-stderr sync_cli check "${ARGS[@]}"
  [[ "$output" == *"stale  docs/unlock.md  agent-core $CORE_VERSION changed it; your copy still matches the lock"* ]]
  run -0 --separate-stderr sync_cli plan "${ARGS[@]}"
  [[ "$output" == *"  replace  docs/unlock.md"*"(template changed; your copy is what setup wrote)"* ]]
  sync_now
  cmp "$K/templates/common/docs/unlock.md" "$P/docs/unlock.md"
  run -0 --separate-stderr sync_cli check "${ARGS[@]}"
}

@test "when both the template and the project copy changed, the file is modified, and sync keeps the user's" {
  setup_now
  echo 'upstream' >>"$K/templates/common/docs/unlock.md"
  echo 'mine' >>"$P/docs/unlock.md"
  mine="$(sha_of "$P/docs/unlock.md")"
  run -1 --separate-stderr sync_cli check "${ARGS[@]}"
  [[ "$output" == *"modified  docs/unlock.md"* && "$output" != *"stale  docs/unlock.md"* ]]
  sync_now
  [ "$(sha_of "$P/docs/unlock.md")" = "$mine" ]
}

@test "a template the lock does not know is new; sync creates it" {
  setup_now
  echo '# added upstream' >"$K/templates/common/docs/added.md"
  run -1 --separate-stderr sync_cli check "${ARGS[@]}"
  [[ "$output" == *"new  docs/added.md  agent-core $CORE_VERSION ships it"* ]]
  sync_now
  cmp "$K/templates/common/docs/added.md" "$P/docs/added.md"
  run -0 --separate-stderr sync_cli check "${ARGS[@]}"
}

@test "a file this version no longer ships is removed-upstream: sync drops it from the lock and never deletes it" {
  setup_now
  rm "$K/templates/common/.claude/CI-RUNNERS.example.md"
  run -1 --separate-stderr sync_cli check "${ARGS[@]}"
  [[ "$output" == *"removed-upstream  .claude/CI-RUNNERS.example.md  agent-core $CORE_VERSION no longer ships it"* ]]
  sync_now
  [ -f "$P/.claude/CI-RUNNERS.example.md" ]
  [ "$(json_q "$P/.claude/agent-config-kit.lock" '".claude/CI-RUNNERS.example.md" in d["plugins"]["agent-core"]["files"]')" = false ]
  run -0 --separate-stderr sync_cli check "${ARGS[@]}"
}

@test "a changed CLAUDE.md fragment or gitignore line is block-stale, reported once per block; sync updates the blocks" {
  setup_now
  echo '- One more line.' >>"$K/templates/common/_kit/claude-md.md"
  python3 - "$K/templates/common/_kit/setup.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["gitignore"].append(".claude/extra/")
open(sys.argv[1], "w").write(json.dumps(d, indent=2) + "\n")
PY
  run -1 --separate-stderr sync_cli check "${ARGS[@]}"
  [ "$(grep -c '^block-stale  CLAUDE.md' <<<"$output")" -eq 1 ]
  [ "$(grep -c '^block-stale  .gitignore' <<<"$output")" -eq 1 ]
  sync_now
  grep -qx -- '- One more line.' "$P/CLAUDE.md"
  grep -qx '.claude/extra/' "$P/.gitignore"
  run -0 --separate-stderr sync_cli check "${ARGS[@]}"
}

@test "a new question takes its recommended answer on sync" {
  setup_now
  python3 - "$K/templates/common/_kit/setup.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["questions"].append({"id": "later", "ask": "A later question?", "why": "A test.", "choices": ["yes", "no"],
                       "recommended": "no", "install": {"yes": ["docs/unlock.md"]}})
open(sys.argv[1], "w").write(json.dumps(d, indent=2) + "\n")
PY
  # docs/unlock.md is now installed only for "yes": with the recommended "no", sync drops it.
  run -1 --separate-stderr sync_cli check "${ARGS[@]}"
  [[ "$output" == *"removed-upstream  docs/unlock.md"* ]]
  sync_now
  [ "$(json_q "$P/.claude/agent-config-kit.lock" 'd["plugins"]["agent-core"]["answers"]["later"]')" = no ]
  [ -f "$P/docs/unlock.md" ]
}

@test "a stack plugin's setup plans agent-core's layer first, in the same draft" {
  X="$BATS_TEST_TMPDIR/agent-x"
  fake_stack "$X" agent-x 2.0.0 x
  printf '{\n  "name": "app"\n}\n' >"$P/package.json"
  stack_args "$X" x "$P"
  run -0 --separate-stderr setup_cli questions "${ARGS[@]}" --json
  [ "$(python3 -c 'import json, sys; print(" ".join(q["plugin"] + ":" + q["id"] for q in json.loads(sys.argv[1])["questions"]))' "$output")" = \
    "agent-core:language agent-core:sandbox agent-core:mcp agent-core:team-plugins agent-x:extra" ]
  run -0 --separate-stderr setup_cli plan "${ARGS[@]}" --answer extra=yes
  [[ "$(head -1 <<<"$output")" == "agent-setup plan · agent-x 2.0.0 + agent-core $CORE_VERSION · project "* ]]
  [[ "$output" == *"  create   scripts/ops/unlock.sh"* && "$output" == *"  create   .claude/rules/x/extra.md"* ]]
  setup_now --answer extra=yes
  [ "$(json_q "$P/.claude/agent-config-kit.lock" 'sorted(d["plugins"])')" = '["agent-core", "agent-x"]' ]
  # One block each, agent-core's section first; package scripts from both.
  [ "$(grep -c '^<!-- >>> agent-config-kit' "$P/CLAUDE.md")" -eq 1 ]
  [ "$(grep -o 'agent-config-kit/agent-[a-z]*' "$P/CLAUDE.md" | tr '\n' ' ')" = "agent-config-kit/agent-core agent-config-kit/agent-x " ]
  grep -qx 'x-cache/' "$P/.gitignore"
  [ "$(json_q "$P/package.json" 'sorted(d["scripts"])')" = '["unlock", "x:check"]' ]
  [ "$(json_q "$P/.claude/settings.json" '"Bash(x extra:*)" in d["permissions"]["allow"]')" = true ]
  run -0 --separate-stderr sync_cli check "${ARGS[@]}"
  # agent-core alone checks its own layer and names the other plugin as unchecked.
  core_args "$P"
  run -0 --separate-stderr sync_cli check "${ARGS[@]}"
  [[ "$output" == *"unchecked  .claude/agent-config-kit.lock  agent-x: its templates were not given"* ]]
}

@test "a stack set up after agent-core adds its layer only, keeping agent-core's block section" {
  setup_now
  X="$BATS_TEST_TMPDIR/agent-x"
  fake_stack "$X" agent-x 2.0.0 x
  stack_args "$X" x "$P"
  run -0 --separate-stderr setup_cli plan "${ARGS[@]}"
  [[ "$(head -1 <<<"$output")" == "agent-setup plan · agent-x 2.0.0 · project "* ]]
  [[ "$output" != *"scripts/ops/unlock.sh"* ]]
  setup_now
  grep -q 'agent-config-kit/agent-core' "$P/CLAUDE.md"
  grep -q 'agent-config-kit/agent-x' "$P/CLAUDE.md"
  run -0 --separate-stderr sync_cli check "${ARGS[@]}"
}

@test "a stack's CLAUDE.md.starter becomes CLAUDE.md when the project has none, then belongs to the project" {
  X="$BATS_TEST_TMPDIR/agent-x"
  fake_stack "$X" agent-x 2.0.0 x
  printf '# Starter for x\n' >"$X/templates/x/CLAUDE.md.starter"
  stack_args "$X" x "$P"
  run -0 --separate-stderr setup_cli plan "${ARGS[@]}"
  [[ "$output" == *"  block    CLAUDE.md"*"(new file) from the starter"* ]]
  setup_now
  [ "$(head -1 "$P/CLAUDE.md")" = "# Starter for x" ]
  grep -qx '## Agent config kit' "$P/CLAUDE.md"
  [ "$(json_q "$P/.claude/agent-config-kit.lock" '"CLAUDE.md" in d["plugins"]["agent-x"]["seeded"]')" = true ]
}

@test "plugins that name each other in conflictsWith cannot both be set up (exit 3)" {
  X="$BATS_TEST_TMPDIR/agent-x" && fake_stack "$X" agent-x 2.0.0 x
  Y="$BATS_TEST_TMPDIR/agent-y" && fake_stack "$Y" agent-y 1.0.0 y
  python3 - "$Y/templates/y/_kit/setup.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["conflictsWith"] = ["agent-x"]
open(sys.argv[1], "w").write(json.dumps(d, indent=2) + "\n")
PY
  stack_args "$X" x "$P"
  setup_now
  stack_args "$Y" y "$P"
  run -3 --separate-stderr setup_cli plan "${ARGS[@]}"
  [[ "$stderr" == *"agent-y conflicts with agent-x, which this project has set up"* ]]
}

@test "a stack's own hook wired in the project settings is double wiring for that stack" {
  X="$BATS_TEST_TMPDIR/agent-x" && fake_stack "$X" agent-x 2.0.0 x
  stack_args "$X" x "$P"
  setup_now
  printf '{"hooks": {"PreToolUse": [{"matcher": "Write", "hooks": [{"type": "command", "command": "bash .claude/hooks/x-guard.sh"}]}]}}\n' \
    >"$P/.claude/settings.local.json"
  run -4 --separate-stderr sync_cli check "${ARGS[@]}"
  [[ "$output" == *"double-wired  .claude/settings.local.json  hooks.PreToolUse[0] runs x-guard.sh, which agent-x also runs"* ]]
}

@test "a malformed setup.json is a usage error: an unknown key, a stack that does not match, a stack declaring unlock" {
  X="$BATS_TEST_TMPDIR/agent-x" && fake_stack "$X" agent-x 2.0.0 x
  stack_args "$X" x "$P"
  cfg="$X/templates/x/_kit/setup.json"
  cp "$cfg" "$BATS_TEST_TMPDIR/setup.json"
  for change in 'd["surprise"] = 1' 'd["stack"] = "other"' 'd["packageScripts"]["unlock"] = "x"' \
    'd["questions"][0]["recommended"] = "maybe"' 'd["questions"][0]["install"] = {"maybe": []}'; do
    python3 - "$BATS_TEST_TMPDIR/setup.json" "$cfg" "$change" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
exec(sys.argv[3])
open(sys.argv[2], "w").write(json.dumps(d))
PY
    run -2 --separate-stderr setup_cli plan "${ARGS[@]}"
    [[ "$stderr" == *"setup.json"* ]] || { echo "no setup.json error for: $change: $stderr" >&2; return 1; }
  done
}

@test "a settings template with a hooks key is refused (exit 2): hooks belong to the plugin" {
  X="$BATS_TEST_TMPDIR/agent-x" && fake_stack "$X" agent-x 2.0.0 x
  printf '{"hooks": {}}\n' >"$X/templates/x/.claude/settings.json"
  python3 - "$X/templates/x/_kit/setup.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["questions"][0].pop("settings")
open(sys.argv[1], "w").write(json.dumps(d))
PY
  stack_args "$X" x "$P"
  run -2 --separate-stderr setup_cli plan "${ARGS[@]}"
  [[ "$stderr" == *"may not hold hooks"* ]]
}

@test "templates that would land as plugin components, a real .env or an unsuffixed CLAUDE.md are refused" {
  X="$BATS_TEST_TMPDIR/agent-x" && fake_stack "$X" agent-x 2.0.0 x
  stack_args "$X" x "$P"
  for bad in .claude/hooks/x.sh .claude/commands/x.md .env.local CLAUDE.md package.json .gitignore; do
    mkdir -p "$(dirname "$X/templates/x/$bad")" && echo x >"$X/templates/x/$bad"
    run -2 --separate-stderr setup_cli plan "${ARGS[@]}"
    [[ "$stderr" == *"$bad"* ]] || { echo "not refused: $bad: $stderr" >&2; return 1; }
    rm "$X/templates/x/$bad"
  done
}

@test "a caller pinned to the release placeholder is held back, then installed by the release that pins a commit" {
  X="$BATS_TEST_TMPDIR/agent-x" && fake_stack "$X" agent-x 2.0.0 x
  mkdir -p "$X/templates/x/.github/workflows"
  caller() { # $1 sha
    printf 'on:\n  pull_request:\npermissions:\n  contents: read\njobs:\n  gate:\n    uses: adhibuchori/agent-config-kit/.github/workflows/x-quality-gate.yml@%s # v1.0.0\n' "$1" \
      >"$X/templates/x/.github/workflows/quality-gate.yml"
  }
  caller "$(printf '0%.0s' {1..40})"
  stack_args "$X" x "$P"
  run -0 --separate-stderr setup_cli plan "${ARGS[@]}"
  [[ "$output" == *"  warn     .github/workflows/quality-gate.yml"*"release placeholder @000"* ]]
  [[ "$output" != *"  create   .github/workflows/quality-gate.yml"* ]]
  setup_now
  [ ! -e "$P/.github/workflows/quality-gate.yml" ]
  [ "$(json_q "$P/.claude/agent-config-kit.lock" '".github/workflows/quality-gate.yml" in d["plugins"]["agent-x"]["files"]')" = false ]
  # Held is not drift: check stays in sync and names the file.
  run -0 --separate-stderr sync_cli check "${ARGS[@]}"
  [[ "$output" == *"held  .github/workflows/quality-gate.yml"* ]]
  [[ "$output" == *"result: in sync"* ]]
  # The next release pins a real commit: it is new, and sync installs it.
  caller 0123456789abcdef0123456789abcdef01234567
  run -1 --separate-stderr sync_cli check "${ARGS[@]}"
  [[ "$output" == *"new  .github/workflows/quality-gate.yml"* ]]
  sync_now
  cmp "$P/.github/workflows/quality-gate.yml" "$X/templates/x/.github/workflows/quality-gate.yml"
  run -0 --separate-stderr sync_cli check "${ARGS[@]}"
}
