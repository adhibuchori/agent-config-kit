#!/usr/bin/env bats
# scripts/skills-plugins.sh on a two-plugin kit, with a stub skillspector that writes the reports the
# real one would and logs what it was asked to scan. The gate itself is the real template skills.sh.
# The fixture baseline is JSON (valid YAML), read through a stand-in yaml module, so no test needs
# PyYAML or the network.

load helpers

setup() {
  ci_isolate
  K="$BATS_TEST_TMPDIR/kit"
  kit_fixture "$K"
  scan_stub
}

kit_fixture() {
  local k="$1" c="$1/plugins/agent-core" d="$1/plugins/agent-demo"
  mkdir -p "$c/templates/common/scripts/check" "$c/scripts" "$c/commands" "$c/hooks" \
    "$d/commands" "$d/agents" "$d/skills/tidy" "$d/scripts" "$d/hooks" "$k/scripts"
  cp "$KIT_ROOT/plugins/agent-core/templates/common/scripts/check/skills.sh" "$c/templates/common/scripts/check/"
  cp "$KIT_ROOT/scripts/skills-plugins.sh" "$k/scripts/"
  printf '# lib\n' >"$c/scripts/lib.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$c/scripts/guard.sh"
  printf -- '---\ndescription: List every command\n---\n\nRun the help.\n' >"$c/commands/help.md"
  printf '{ "hooks": {} }\n' >"$c/hooks/hooks.json"
  cp "$c/scripts/lib.sh" "$d/scripts/lib.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$d/scripts/demo-guard.sh"
  printf -- '---\ndescription: Install the demo rules\n---\n\nSet up.\n' >"$d/commands/setup.md"
  printf -- '---\nname: reviewer\ndescription: Reviews a demo change\n---\n' >"$d/agents/reviewer.md"
  printf -- '---\nname: tidy\ndescription: Use when tidying\n---\n' >"$d/skills/tidy/SKILL.md"
  printf '{ "hooks": {} }\n' >"$d/hooks/hooks.json"
  cat >"$c/templates/common/.skillspector-baseline.yaml" <<'EOF'
{"version": 2, "rules": [], "vendored": [], "partial": [
  {"target": ".claude/hooks", "path": "lib.sh", "reason_code": "static_parse_limit", "reason": "embedded analyzer"}
]}
EOF
}

# skillspector: --version, and `scan <path> ... -o <report>`. A file holding FLAGGED gets a HIGH
# finding; lib.sh gets the partial ledger row the baseline names; a target holding FLAKY fails its
# first scan only. Each scan logs the target, its files and the baseline it was given.
scan_stub() {
  STUBS="$BATS_TEST_TMPDIR/stubs" PYLIB="$BATS_TEST_TMPDIR/pylib"
  STUB_LOG="$BATS_TEST_TMPDIR/scan.log"
  mkdir -p "$STUBS" "$PYLIB"
  : >"$STUB_LOG"
  cat >"$PYLIB/yaml.py" <<'EOF'
import json
def safe_load(stream):
    return json.load(stream) if hasattr(stream, "read") else json.loads(stream)
def safe_dump(data, stream, sort_keys=False):
    json.dump(data, stream)
EOF
  cat >"$STUBS/skillspector" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "SkillSpector v2.11.2"; exit 0; fi
shift
target="$1" report="" baseline=""
while [ $# -gt 0 ]; do
  case "$1" in -o) report="$2"; shift ;; --baseline) baseline="$2"; shift ;; esac
  shift
done
files="$(find "$target" -type f | sort | tr '\n' ' ')"
printf 'scan %s | %s| baseline=%s\n' "$target" "$files" "$( [ -n "$baseline" ] && tr -d '\n ' <"$baseline")" >>"$STUB_LOG"
if grep -rqs FLAKY "$target" && [ ! -e "$BATS_TEST_TMPDIR/flaky.done" ]; then
  : >"$BATS_TEST_TMPDIR/flaky.done"
  exit 3
fi
issues='[]'
grep -rqs FLAGGED "$target" && issues='[{"id": "PE2", "severity": "HIGH", "category": "privilege", "location": {"file": "x.md", "start_line": 1}, "explanation": "flagged"}]'
ledger='[]'
[ -f "$target/lib.sh" ] && ledger='[{"path": "lib.sh", "reason_code": "static_parse_limit", "message": "long", "fatal": false}]'
cat >"$report" <<JSON
{"issues": $issues, "execution_successful": true, "suppressed_count": 0, "risk_assessment": {"score": 0},
 "metadata": {}, "analysis_completeness": {"status": "complete", "ledger_exceptions": $ledger, "analyzer_statuses": []}}
JSON
[ "$issues" = '[]' ] || exit 1
exit 0
EOF
  chmod +x "$STUBS/skillspector"
  export STUBS STUB_LOG PATH="$STUBS:$PATH" PYTHONPATH="$PYLIB"
}

run_scan() { run bash "$K/scripts/skills-plugins.sh" --root "$K" "$@"; }

@test "skills-plugins: clean plugins pass, and every component kind is scanned" {
  run_scan
  [ "$status" -eq 0 ]
  [[ "$output" == *"skills-plugins: 2 plugin(s) scanned"* ]]
  grep -q 'scan .claude/commands/help.md' "$STUB_LOG"
  grep -q 'scan .claude/agents/reviewer.md' "$STUB_LOG"
  grep -q 'scan .claude/skills/tidy' "$STUB_LOG"
  [ "$(grep -c 'scan .claude/hooks' "$STUB_LOG")" -eq 2 ]
}

@test "skills-plugins: lib.sh is scanned once, with agent-core, and its baseline entries only there" {
  run_scan
  [ "$status" -eq 0 ]
  [ "$(grep 'scan .claude/hooks' "$STUB_LOG" | grep -c 'hooks/lib.sh')" -eq 1 ]
  grep 'scan .claude/hooks' "$STUB_LOG" | grep 'hooks/lib.sh' | grep -q 'hooks/guard.sh'
  # agent-core keeps the lib.sh entry; the plugin scanned without lib.sh gets none, so nothing is stale.
  grep 'scan .claude/hooks' "$STUB_LOG" | grep 'hooks/lib.sh' | grep -q '"path":"lib.sh"'
  grep 'scan .claude/hooks' "$STUB_LOG" | grep 'demo-guard.sh' | grep -q '"partial":\[\]'
  [[ "$output" != *"matched nothing"* ]]
}

@test "skills-plugins: hooks.json is never staged" {
  run_scan
  [ "$status" -eq 0 ]
  run ! grep -q 'hooks.json' "$STUB_LOG"
}

@test "skills-plugins: a finding fails and names its plugin" {
  printf '\nFLAGGED\n' >>"$K/plugins/agent-demo/commands/setup.md"
  run_scan
  [ "$status" -eq 1 ]
  [[ "$output" == *"agent-demo: SkillSpector found something its gate refuses"* ]]
  [[ "$output" != *"agent-core: SkillSpector found"* ]]
}

@test "skills-plugins: a scan that fails once passes on the second run, with a warning" {
  printf '\nFLAKY\n' >>"$K/plugins/agent-demo/agents/reviewer.md"
  run_scan
  [ "$status" -eq 0 ]
  [[ "$output" == *"agent-demo passed only on the second run"* ]]
}

@test "skills-plugins: --base fails when the change adds to the baseline, and passes when it removes" {
  local b="$K/plugins/agent-core/templates/common/.skillspector-baseline.yaml"
  git -C "$K" init -q -b main && git -C "$K" add -A && git -C "$K" commit -qm base
  git -C "$K" checkout -q -b feature
  cat >"$b" <<'EOF'
{"version": 2, "rules": [], "vendored": [], "partial": [
  {"target": ".claude/hooks", "path": "x.sh", "reason_code": "y", "reason": "z"},
  {"target": ".claude/hooks", "path": "lib.sh", "reason_code": "static_parse_limit", "reason": "embedded analyzer"}
]}
EOF
  git -C "$K" commit -qam grow
  run_scan --base main
  [ "$status" -eq 1 ]
  [[ "$output" == *"this change adds to the SkillSpector baseline"* ]]
  [[ "$output" == *'"path": "x.sh"'* ]]
  git -C "$K" checkout -q main && git -C "$K" checkout -q -b shrink
  sed -i.bak '/"path": "lib.sh"/d' "$b" && rm -f "$b.bak"
  git -C "$K" commit -qam shrink
  run_scan --base main
  [[ "$output" != *"adds to the SkillSpector baseline"* ]]
}

@test "skills-plugins: a bad argument or a folder that is not the kit exits 2" {
  run bash "$K/scripts/skills-plugins.sh" --nope
  [ "$status" -eq 2 ]
  run bash "$K/scripts/skills-plugins.sh" --root "$BATS_TEST_TMPDIR"
  [ "$status" -eq 2 ]
}
