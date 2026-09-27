#!/usr/bin/env bats
# agent-sync check: one line per finding, a deterministic exit code (0 in sync, 1 drift,
# 4 double wiring, 5 both), and agent-sync plan/apply/own to bring the project back.

load ../helpers/common

setup() {
  kit_isolate "$BATS_TEST_TMPDIR/env"
  P="$BATS_TEST_TMPDIR/proj"
  new_repo "$P"
  core_args "$P"
  printf '{\n  "name": "app"\n}\n' >"$P/package.json"
  setup_now
}

# $1 exit code, $2 the finding line check must print.
expect_finding() {
  run "-$1" --separate-stderr sync_cli check "${ARGS[@]}"
  [[ "$output" == *"$2"* ]] || {
    printf 'expected finding: %s\ngot:\n%s\n' "$2" "$output" >&2
    return 1
  }
}

@test "a managed file that is gone is missing (exit 1); sync restores it" {
  rm "$P/docs/unlock.md"
  expect_finding 1 "missing  docs/unlock.md  setup wrote it; it is gone"
  run -0 --separate-stderr sync_cli plan "${ARGS[@]}"
  [[ "$output" == *"  create   docs/unlock.md"*"(missing; restored from the template)"* ]]
  sync_now
  cmp "$COMMON/docs/unlock.md" "$P/docs/unlock.md"
  run -0 --separate-stderr sync_cli check "${ARGS[@]}"
}

@test "a managed file the user edited is modified (exit 1); sync never touches it" {
  echo '# mine' >>"$P/scripts/env/show.sh"
  mine="$(sha_of "$P/scripts/env/show.sh")"
  expect_finding 1 "modified  scripts/env/show.sh  differs from what setup wrote"
  run -0 --separate-stderr sync_cli plan "${ARGS[@]}"
  [[ "$output" == *"  modified scripts/env/show.sh"*"keep it: agent-sync own scripts/env/show.sh; take the kit's: delete it, then sync again"* ]]
  sync_now
  [ "$(sha_of "$P/scripts/env/show.sh")" = "$mine" ]
  run -1 --separate-stderr sync_cli check "${ARGS[@]}"
}

@test "own hands an edited file to the project, and --undo hands it back without taking the user's bytes as the kit's" {
  echo '# mine' >>"$P/scripts/env/show.sh"
  run -0 --separate-stderr sync_cli own "${ARGS[@]}" scripts/env/show.sh
  [[ "$output" == *"own      scripts/env/show.sh  (yours; sync no longer compares it)"* ]]
  expect_finding 0 "owned  scripts/env/show.sh  yours (agent-sync own); not compared"
  run -0 --separate-stderr sync_cli own "${ARGS[@]}" --undo scripts/env/show.sh
  # Back under the kit, the edited copy is modified again, never stale: sync must not replace it.
  expect_finding 1 "modified  scripts/env/show.sh  differs from what setup wrote"
  run -0 --separate-stderr sync_cli plan "${ARGS[@]}"
  [[ "$output" != *"replace  scripts/env/show.sh"* ]]
  run -2 --separate-stderr sync_cli own "${ARGS[@]}" no/such/file
  [[ "$stderr" == *"no/such/file is not a managed path of agent-core in the lock"* ]]
}

@test "deleting an edited file and syncing takes the kit's copy again" {
  echo '# mine' >>"$P/scripts/env/show.sh"
  rm "$P/scripts/env/show.sh"
  sync_now
  cmp "$COMMON/scripts/env/show.sh" "$P/scripts/env/show.sh"
  run -0 --separate-stderr sync_cli check "${ARGS[@]}"
}

@test "a script that lost its exec bit is mode (exit 1); sync restores the bit only" {
  chmod -x "$P/scripts/ops/unlock.sh"
  expect_finding 1 "mode  scripts/ops/unlock.sh  lost its exec bit"
  sync_now
  [ -x "$P/scripts/ops/unlock.sh" ]
  cmp "$COMMON/scripts/ops/unlock.sh" "$P/scripts/ops/unlock.sh"
  run -0 --separate-stderr sync_cli check "${ARGS[@]}"
}

@test "a settings entry setup added and the user removed is settings-missing (exit 1); sync adds it back" {
  python3 - "$P/.claude/settings.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["permissions"]["deny"].remove("Read(.env*)")
open(sys.argv[1], "w").write(json.dumps(d, indent=2) + "\n")
PY
  expect_finding 1 'settings-missing  .claude/settings.json  /permissions/deny "Read(.env*)"'
  sync_now
  [ "$(json_q "$P/.claude/settings.json" '"Read(.env*)" in d["permissions"]["deny"]')" = true ]
  run -0 --separate-stderr sync_cli check "${ARGS[@]}"
}

@test "an edited .gitignore block is block-modified (exit 1); sync leaves it and says how to recover" {
  python3 - "$P/.gitignore" <<'PY'
import sys
p = sys.argv[1]
text = open(p).read()
open(p, "w").write(text.replace(".claude/session-logs/\n", ""))
PY
  before="$(sha_of "$P/.gitignore")"
  expect_finding 1 "block-modified  .gitignore  the agent-config-kit block was edited by hand"
  run -0 --separate-stderr sync_cli plan "${ARGS[@]}"
  [[ "$output" == *"  conflict .gitignore"*"move your lines outside it and delete the block, then sync again"* ]]
  sync_now
  [ "$(sha_of "$P/.gitignore")" = "$before" ]
}

@test "a CLAUDE.md block the user deleted is block-missing (exit 1); sync writes it again" {
  printf '# Rewritten by hand\n' >"$P/CLAUDE.md"
  expect_finding 1 "block-missing  CLAUDE.md  the agent-config-kit block is gone"
  sync_now
  [ "$(head -1 "$P/CLAUDE.md")" = "# Rewritten by hand" ]
  grep -qx '## Agent config kit' "$P/CLAUDE.md"
  run -0 --separate-stderr sync_cli check "${ARGS[@]}"
}

@test "an unlock script removed from package.json is alias-missing (exit 1); sync adds it back" {
  printf '{\n  "name": "app"\n}\n' >"$P/package.json"
  expect_finding 1 "alias-missing  package.json  scripts.unlock is missing"
  sync_now
  [ "$(json_q "$P/package.json" 'd["scripts"]["unlock"]')" = "bash scripts/ops/unlock.sh" ]
  run -0 --separate-stderr sync_cli check "${ARGS[@]}"
}

@test "a package.json that appears after setup without the alias is alias-missing" {
  Q="$BATS_TEST_TMPDIR/py" && new_repo "$Q" && core_args "$Q"
  setup_now
  run -0 --separate-stderr sync_cli check "${ARGS[@]}"
  printf '{"name": "tools"}\n' >"$Q/package.json"
  expect_finding 1 "alias-missing  package.json  scripts.unlock is missing"
}

@test "opted in with .claude/agent-config.json but never set up is no-lock (exit 1)" {
  Q="$BATS_TEST_TMPDIR/optin" && new_repo "$Q" && core_args "$Q"
  mkdir -p "$Q/.claude" && echo '{}' >"$Q/.claude/agent-config.json"
  expect_finding 1 "no-lock  .claude/agent-config-kit.lock  agent-core: setup has not run: .claude/agent-config.json opts the project in, but there is no lock; run /agent-core:setup"
}

@test "a hook the project's settings also wires is double-wired (exit 4), in settings.json or settings.local.json" {
  python3 - "$P/.claude/settings.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["hooks"] = {"PostToolUse": [{"matcher": "Write", "hooks": [
    {"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/post-edit.sh\"", "timeout": 60}]}]}
open(sys.argv[1], "w").write(json.dumps(d, indent=2) + "\n")
PY
  expect_finding 4 "double-wired  .claude/settings.json  hooks.PostToolUse[0] runs post-edit.sh, which agent-core also runs"
  [[ "$output" == *"result: double wiring (1 finding; exit 4)"* ]]
  printf '{"hooks": {"PreToolUse": [{"matcher": "mcp__.*", "hooks": [{"type": "command", "command": "bash .claude/hooks/db-guard.sh"}]}]}}\n' \
    >"$P/.claude/settings.local.json"
  expect_finding 4 "double-wired  .claude/settings.local.json  hooks.PreToolUse[0] runs db-guard.sh, which agent-core also runs"
}

@test "drift and double wiring together exit 5; --json carries the same findings and exit" {
  rm "$P/docs/unlock.md"
  printf '{"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash .claude/hooks/safety-check.sh"}]}]}}\n' \
    >"$P/.claude/settings.local.json"
  expect_finding 5 "result: drift and double wiring (2 findings; exit 5)"
  text="$output"
  run -5 --separate-stderr sync_cli check "${ARGS[@]}" --json
  python3 - "$output" "$text" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
assert d["plugin"] == "agent-core" and d["exit"] == 5, d
kinds = [f["kind"] for f in d["findings"]]
assert kinds == sorted(kinds), kinds
assert {"double-wired", "missing"} <= set(kinds), kinds
for f in d["findings"]:
    assert f"{f['kind']}  {f['path']}  {f['detail']}" in sys.argv[2], f
PY
}

@test "check writes nothing and prints the same bytes on every run" {
  rm "$P/docs/unlock.md" && chmod -x "$P/scripts/ops/unlock.sh"
  before="$(tree_state "$P")"
  run -1 --separate-stderr sync_cli check "${ARGS[@]}"
  first="$output"
  run -1 --separate-stderr sync_cli check "${ARGS[@]}"
  [ "$output" = "$first" ]
  [ "$(tree_state "$P")" = "$before" ]
}

@test "seeded files are the project's own: editing or deleting one is never drift" {
  echo '{"mcpServers": {"mine": {}}}' >"$P/.mcp.json"
  rm "$P/.skillspector-baseline.yaml"
  expect_finding 0 "seeded  .mcp.json  created once; the project's own"
}

@test "sync apply refuses a stale digest and writes nothing" {
  rm "$P/docs/unlock.md"
  run -0 --separate-stderr sync_cli plan "${ARGS[@]}"
  digest="$(digest_of "$output")"
  chmod -x "$P/scripts/ops/unlock.sh"
  before="$(tree_state "$P")"
  run -3 --separate-stderr sync_cli apply "${ARGS[@]}" --digest "$digest"
  [ "$(tree_state "$P")" = "$before" ]
}

@test "sync on a project that was never set up plans nothing, and apply is refused" {
  Q="$BATS_TEST_TMPDIR/fresh" && new_repo "$Q" && core_args "$Q"
  run -0 --separate-stderr sync_cli plan "${ARGS[@]}"
  [ "$output" = "agent-sync plan · nothing is set up here: run /agent-core:setup" ]
  run -3 --separate-stderr sync_cli apply "${ARGS[@]}" --digest "sha256:$(printf '0%.0s' {1..64})"
}

@test "a lock that is not JSON is an I/O error (exit 2), not a silent pass" {
  echo garbage >"$P/.claude/agent-config-kit.lock"
  run -2 --separate-stderr sync_cli check "${ARGS[@]}"
  [[ "$stderr" == *"agent-config-kit.lock is not readable JSON"* ]]
}

@test "a lock with the wrong shape is a usage error (exit 2), never a traceback read as drift" {
  for bad in '{"plugins": {"agent-core": {"files": []}}}' \
             '{"plugins": {"agent-core": {"kept": "x"}}}' \
             '{"plugins": {"agent-core": []}}' \
             '{"plugins": {"agent-core": {"settings": {"no-pointer": 1}}}}' \
             '{"plugins": {}, "blocks": []}'; do
    printf '%s\n' "$bad" >"$P/.claude/agent-config-kit.lock"
    run -2 --separate-stderr sync_cli check "${ARGS[@]}"
    [[ "$stderr" == *"agent-config-kit.lock is malformed"* ]] || { echo "not a usage error: $bad: $stderr" >&2; return 1; }
    [[ "$stderr" != *"Traceback"* ]]
  done
}
