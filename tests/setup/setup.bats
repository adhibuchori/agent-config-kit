#!/usr/bin/env bats
# shellcheck disable=SC2016 # single-quoted JSON holds a literal "$schema" key
# agent-setup on a fresh project: questions, the draft, the digest that gates apply, what apply
# writes, and the lock. Every test builds its own git repo under $BATS_TEST_TMPDIR.

load ../helpers/common

setup() {
  kit_isolate "$BATS_TEST_TMPDIR/env"
  P="$BATS_TEST_TMPDIR/proj"
  new_repo "$P"
  core_args "$P"
}

@test "questions --json lists agent-core's questions, each recommending one of its choices" {
  run -0 --separate-stderr setup_cli questions "${ARGS[@]}" --json
  python3 - "$output" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
assert d["plugin"] == "agent-core" and d["stack"] == "common", d
ids = [q["id"] for q in d["questions"]]
assert ids == ["language", "sandbox", "mcp", "team-plugins"], ids
for q in d["questions"]:
    assert {"id", "ask", "why", "choices", "recommended", "detect"} <= set(q), q
    assert q["recommended"] in q["choices"], q
PY
}

@test "plan drafts every template file and writes nothing" {
  before="$(tree_state "$P")"
  run -0 --separate-stderr setup_cli plan "${ARGS[@]}"
  [[ "$output" == "agent-setup plan · agent-core 1.0.0 · project "* ]]
  [[ "$output" == *"  create   scripts/ops/unlock.sh"* ]]
  [[ "$output" == *"  create   .claude/settings.json"* ]]
  [[ "$output" == *"  seed     .mcp.json"* ]]
  [[ "$output" == *"  block    .gitignore"* ]]
  [[ "$output" == *"  block    CLAUDE.md"* ]]
  [[ "$output" == *"  note     package.json"*"./scripts/ops/unlock.sh"* ]]
  # The lock is the last action and the digest the last line.
  [[ "$(tail -2 <<<"$output" | head -1)" == "  lock     .claude/agent-config-kit.lock"* ]]
  [[ "$(tail -1 <<<"$output")" =~ ^digest\ sha256:[0-9a-f]{64}$ ]]
  [ "$(tree_state "$P")" = "$before" ]
}

@test "plan --json carries the same digest and the actions in draft order" {
  run -0 --separate-stderr setup_cli plan "${ARGS[@]}"
  human="$(digest_of "$output")"
  run -0 --separate-stderr setup_cli plan "${ARGS[@]}" --json
  python3 - "$output" "$human" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
assert d["digest"] == sys.argv[2], (d["digest"], sys.argv[2])
assert d["plugins"] == [{"name": "agent-core", "version": "1.0.0"}], d["plugins"]
kinds = [a["kind"] for a in d["actions"]]
assert kinds[-1] == "lock" and kinds.index("create") < kinds.index("seed") < kinds.index("block"), kinds
assert all(set(a) == {"kind", "path", "detail"} for a in d["actions"])
PY
}

@test "apply needs the digest: missing is a usage error, a wrong one is refused and writes nothing" {
  before="$(tree_state "$P")"
  run -2 --separate-stderr setup_cli apply "${ARGS[@]}"
  [[ "$stderr" == *"--digest"* ]]
  run -3 --separate-stderr setup_cli apply "${ARGS[@]}" --digest "sha256:$(printf '0%.0s' {1..64})"
  [[ "$stderr" == *"changed since the draft"*"nothing was written"* ]]
  [ "$(tree_state "$P")" = "$before" ]
}

@test "apply writes the template bytes and modes, and the lock last" {
  setup_now
  for f in scripts/ops/unlock.sh scripts/env/show.sh scripts/env/envfile.py docs/unlock.md .claude/rules/common/folder-shape.md; do
    cmp "$COMMON/$f" "$P/$f"
  done
  [ -x "$P/scripts/ops/unlock.sh" ] && [ -x "$P/scripts/env/set.sh" ]
  [ ! -x "$P/scripts/env/envfile.py" ] && [ ! -x "$P/docs/unlock.md" ]
  # The lock is written last (its presence turns the hooks on): no file setup wrote is newer.
  [ -z "$(find "$P" -path "$P/.git" -prune -o -type f -newer "$P/.claude/agent-config-kit.lock" -print)" ]
  # No template may carry hook wiring: that is the plugin's hooks/hooks.json.
  [ "$(json_q "$P/.claude/settings.json" '"hooks" in d')" = false ]
  [ ! -e "$P/.claude/hooks" ]
  [ ! -e "$P/package.json" ]
}

@test "the lock records versions, answers and the hash of every file it manages, and nothing machine-specific" {
  setup_now
  lock="$P/.claude/agent-config-kit.lock"
  [ "$(json_q "$lock" 'd["kit"]')" = agent-config-kit ]
  [ "$(json_q "$lock" 'd["lockVersion"]')" = 1 ]
  [ "$(json_q "$lock" 'd["plugins"]["agent-core"]["version"]')" = "$(json_q "$CORE/.claude-plugin/plugin.json" 'd["version"]')" ]
  [ "$(json_q "$lock" 'd["plugins"]["agent-core"]["answers"]')" = '{"language": "typescript", "mcp": "yes", "sandbox": "yes", "team-plugins": "yes"}' ]
  [ "$(json_q "$lock" 'd["plugins"]["agent-core"]["files"]["scripts/ops/unlock.sh"]')" = "$(sha_of "$COMMON/scripts/ops/unlock.sh")" ]
  [ "$(json_q "$lock" 'sorted(d["plugins"]["agent-core"]["seeded"])')" = '[".claude/rules/common/working-agreements.md", ".gitleaks.toml", ".mcp.json", ".skillspector-baseline.yaml"]' ]
  run ! grep -q "$BATS_TEST_TMPDIR" "$lock"
  run ! grep -q "$KIT_ROOT" "$lock"
  # Deterministic JSON: sorted keys, two-space indent, one trailing newline.
  python3 - "$lock" <<'PY'
import json, sys
text = open(sys.argv[1], encoding="utf-8").read()
assert text == json.dumps(json.loads(text), indent=2, sort_keys=True, ensure_ascii=False) + "\n"
PY
}

@test "two identical projects get the same lock, bytes and all, and the draft is the same on every run" {
  Q="$BATS_TEST_TMPDIR/twin"
  new_repo "$Q"
  run -0 --separate-stderr setup_cli plan "${ARGS[@]}"
  first="$output"
  run -0 --separate-stderr setup_cli plan "${ARGS[@]}"
  [ "$output" = "$first" ]
  setup_now
  core_args "$Q"
  setup_now
  cmp "$P/.claude/agent-config-kit.lock" "$Q/.claude/agent-config-kit.lock"
}

@test "right after setup, agent-sync check is in sync (exit 0)" {
  setup_now
  run -0 --separate-stderr sync_cli check "${ARGS[@]}"
  [[ "$output" == *"result: in sync (0 findings; exit 0)"* ]]
}

@test "setup a second time plans nothing and points at sync" {
  setup_now
  before="$(tree_state "$P")"
  run -0 --separate-stderr setup_cli plan "${ARGS[@]}"
  [ "$output" = "already set up (agent-core 1.0.0); run /agent-core:sync" ]
  [ "$(tree_state "$P")" = "$before" ]
}

@test "answers pick what is installed: python rules, no sandbox, no .mcp.json, no team plugins" {
  setup_now --answer language=python --answer sandbox=no --answer mcp=no --answer team-plugins=no
  [ -f "$P/.claude/rules/python/types.md" ] && [ ! -e "$P/.claude/rules/typescript" ]
  [ ! -e "$P/scripts/check/double-assertion.sh" ]
  [ ! -e "$P/.mcp.json" ]
  [ "$(json_q "$P/.claude/settings.json" 'sorted(d)')" = '["$schema", "permissions"]' ]
  [ "$(json_q "$P/.claude/agent-config-kit.lock" 'd["plugins"]["agent-core"]["answers"]["language"]')" = python ]
  run -0 --separate-stderr sync_cli check "${ARGS[@]}"
}

@test "an unknown question, a value outside the choices, or a malformed answer is a usage error" {
  run -2 --separate-stderr setup_cli plan "${ARGS[@]}" --answer nope=yes
  [[ "$stderr" == *"no question 'nope'"* ]]
  run -2 --separate-stderr setup_cli plan "${ARGS[@]}" --answer language=rust
  [[ "$stderr" == *"choose one of typescript, python, both"* ]]
  run -2 --separate-stderr setup_cli plan "${ARGS[@]}" --answer language
  [[ "$stderr" == *"ID=VALUE"* ]]
}

@test "usage errors exit 2: no subcommand, an unknown one, an unknown stack" {
  run -2 --separate-stderr setup_cli
  run -2 --separate-stderr setup_cli frob "${ARGS[@]}"
  run -2 --separate-stderr sync_cli questions "${ARGS[@]}"
  run -2 --separate-stderr setup_cli plan --templates "$TEMPLATES" --stack nope --project "$P"
  run -2 --separate-stderr setup_cli plan --templates "$TEMPLATES" --stack ../common --project "$P"
}

@test "without python3 both programs stop with exit 2 and say why" {
  run -2 --separate-stderr env PATH="$BATS_TEST_TMPDIR/empty" "$HOOK_BASH" "$CORE/bin/agent-setup" plan "${ARGS[@]}"
  [[ "$stderr" == *"python3 (3.8 or newer) is required"* ]]
  run -2 --separate-stderr env PATH="$BATS_TEST_TMPDIR/empty" "$HOOK_BASH" "$CORE/bin/agent-sync" check "${ARGS[@]}"
  [[ "$stderr" == *"python3 (3.8 or newer) is required"* ]]
}

@test "the programs run through a symlink to them, as a PATH entry might hold them" {
  ln -s "$CORE/bin/agent-setup" "$BATS_TEST_TMPDIR/agent-setup"
  run -0 --separate-stderr "$BATS_TEST_TMPDIR/agent-setup" plan "${ARGS[@]}"
  [[ "$output" == "agent-setup plan"* ]]
}

@test "the kit repository, its plugins/ and a plugin folder are refused as projects (exit 3)" {
  for bad in "$KIT_ROOT" "$KIT_ROOT/plugins" "$CORE" "$CORE/templates/common"; do
    run -3 --separate-stderr setup_cli plan --templates "$TEMPLATES" --stack common --project "$bad"
    [[ "$stderr" == *"run setup in your own project"* ]]
  done
}

@test "a folder symlinked out of the project is refused, and nothing is written through it" {
  mkdir -p "$BATS_TEST_TMPDIR/outside"
  ln -s "$BATS_TEST_TMPDIR/outside" "$P/scripts"
  run -3 --separate-stderr setup_cli plan "${ARGS[@]}"
  [[ "$stderr" == *"resolves outside the project"* ]]
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/outside")" ]
}

@test "a template tree holding a symlink is refused (exit 2)" {
  ENGINE_CORE="$(copy_core "$BATS_TEST_TMPDIR/kit")"
  core_args "$P"
  ln -s /etc/hosts "$ENGINE_CORE/templates/common/docs/hosts.md"
  run -2 --separate-stderr setup_cli plan "${ARGS[@]}"
  [[ "$stderr" == *"docs/hosts.md is a symlink"* ]]
}

@test "a file that appears after the draft makes apply refuse, and nothing is written" {
  run -0 --separate-stderr setup_cli plan "${ARGS[@]}"
  digest="$(digest_of "$output")"
  mkdir -p "$P/docs" && echo mine >"$P/docs/unlock.md"
  before="$(tree_state "$P")"
  run -3 --separate-stderr setup_cli apply "${ARGS[@]}" --digest "$digest"
  [ "$(tree_state "$P")" = "$before" ]
  [ ! -e "$P/.claude/agent-config-kit.lock" ]
}

@test "--project defaults to the git top level of the current folder" {
  mkdir -p "$P/sub/dir"
  cd "$P/sub/dir"
  run -0 --separate-stderr setup_cli plan --templates "$TEMPLATES" --stack common
  # Outside the project root the header names the project by its physical path.
  [ "$(head -1 <<<"$output")" = "agent-setup plan · agent-core 1.0.0 · project $(cd "$P" && pwd -P)" ]
  cd "$P"
  run -0 --separate-stderr setup_cli plan --templates "$TEMPLATES" --stack common
  [ "$(head -1 <<<"$output")" = "agent-setup plan · agent-core 1.0.0 · project ." ]
}
