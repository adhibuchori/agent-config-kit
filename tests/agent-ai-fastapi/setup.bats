#!/usr/bin/env bats
# /agent-ai-fastapi:setup and :sync end to end, through agent-core's engine with this plugin's
# templates: the questions, the draft and its digest, no-clobber, the pyproject.toml by-hand line,
# no package.json, the pipeline shape, drift, own, double wiring and a conflicting stack.

load helpers

setup() {
  ai_setup_env
  ai_engine || skip "agent-core's bin/agent-setup and bin/agent-sync are not built yet"
  make_project service
  ai_args
}

@test "questions: agent-core's layer first, then this plugin's five, each recommending one of its choices" {
  run -0 --separate-stderr "$SETUP_BIN" questions "${ARGS[@]}" --json
  run -0 python3 -c '
import json, sys
d = json.loads(sys.argv[1])
assert d["plugin"] == "agent-ai-fastapi" and d["stack"] == "ai-fastapi", d
ids = [(q["plugin"], q["id"]) for q in d["questions"]]
assert ids[0] == ("agent-core", "language"), ids
assert [i for p, i in ids if p == "agent-ai-fastapi"] == ["pipeline", "ci-gate", "pr-templates", "analytics", "serena-workspace"], ids
assert all(q["recommended"] in q["choices"] and q["why"] for q in d["questions"])
print("ok")' "$output"
  [ "$output" = ok ]
}

@test "an unknown answer is a usage error, and apply writes nothing without the draft's digest" {
  run -2 --separate-stderr "$SETUP_BIN" plan "${ARGS[@]}" --answer pipeline=maybe
  run -2 --separate-stderr "$SETUP_BIN" plan "${ARGS[@]}" --answer shape=pipeline
  run -3 --separate-stderr "$SETUP_BIN" apply "${ARGS[@]}" --digest "sha256:$(printf '0%.0s' {1..64})"
  [[ "$stderr" == *"the project changed since the draft"* ]] || false
  [ ! -e "$PROJ/.claude/agent-config-kit.lock" ]
  [ ! -e "$PROJ/AGENTS.md" ]
  run git -C "$PROJ" status --porcelain --untracked-files=all
  [ -z "$output" ]
}

@test "the draft: pyproject.toml kept with a by-hand line, no package.json, CLAUDE.md from the starter" {
  run -0 --separate-stderr "$SETUP_BIN" plan "${ARGS[@]}" --answer language=python
  [[ "$output" == *"agent-setup plan · agent-ai-fastapi $PLUGIN_VERSION + agent-core $CORE_VERSION · project "* ]] || false
  grep -qE '^  keep +pyproject\.toml +\(exists; left alone; compare with agent-ai-fastapi templates/ai-fastapi/pyproject\.toml\.starter\)$' <<<"$output"
  grep -qE '^  by-hand +pyproject\.toml +add what .*/templates/ai-fastapi/_kit/snippets/pyproject\.tools\.toml holds' <<<"$output"
  grep -qE '^  note +package\.json +none here, so no unlock script is added; unlock runs as \./scripts/ops/unlock\.sh$' <<<"$output"
  grep -qE '^  block +CLAUDE\.md +## Agent config kit \(new file\) from the starter$' <<<"$output"
  grep -qE '^  seed +AGENTS\.md ' <<<"$output"
  # The CI caller: created once a release pins a real commit, held back (warn) until then.
  if grep -Eq '@0{40}' "$TPL/.github/workflows/quality-gate.yml"; then
    grep -qE '^  warn +\.github/workflows/quality-gate\.yml +not installed: .*release placeholder' <<<"$output"
  else
    grep -qE '^  create +\.github/workflows/quality-gate\.yml' <<<"$output"
  fi
  grep -qE '^  lock +\.claude/agent-config-kit\.lock +written last; turns the hooks on$' <<<"$output"
  [[ "${lines[${#lines[@]} - 1]}" =~ ^digest\ sha256:[0-9a-f]{64}$ ]] || false
  # pipeline=no by default: the example is not in the draft.
  run ! grep -q 'examples/pipeline' <<<"$output"
}

@test "setup writes the draft and nothing else: pyproject.toml untouched, no package.json, lock last" {
  local before
  before="$(shasum -a 256 "$PROJ/pyproject.toml")"
  ai_setup --answer language=python
  [ "$(shasum -a 256 "$PROJ/pyproject.toml")" = "$before" ]
  [ ! -e "$PROJ/package.json" ]
  [ -f "$PROJ/.claude/agent-config-kit.lock" ]
  cmp "$PROJ/AGENTS.md" "$TPL/AGENTS.md.starter"
  cmp "$PROJ/SSOT.md" "$TPL/SSOT.md.starter"
  cmp "$PROJ/.claude/rules/backend/providers.md" "$TPL/.claude/rules/backend/providers.md"
  cmp "$PROJ/scripts/check/coverage-policy.mjs" "$TPL/scripts/check/coverage-policy.mjs"
  # The CI caller is installed once a release pins a real commit; until then setup holds it back.
  if grep -Eq '@0{40}' "$TPL/.github/workflows/quality-gate.yml"; then
    [ ! -e "$PROJ/.github/workflows/quality-gate.yml" ]
    grep -q 'warn     .github/workflows/quality-gate.yml' <<<"$PLAN"
  else
    cmp "$PROJ/.github/workflows/quality-gate.yml" "$TPL/.github/workflows/quality-gate.yml"
  fi
  [ -f "$PROJ/.github/PULL_REQUEST_TEMPLATE/dev.md" ]
  [ -f "$PROJ/.claude/rules/python/types.md" ]
  [ ! -e "$PROJ/.claude/rules/typescript" ]
  [ ! -e "$PROJ/.claude/examples" ]
  [ ! -e "$PROJ/.claude/ANALYTICS.example.md" ]
  [ ! -e "$PROJ/.claude/SERENA-WORKSPACE.example.md" ]
  [ -x "$PROJ/scripts/ops/unlock.sh" ]
  # CLAUDE.md: the starter, then one managed block holding this plugin's fragment.
  [ "$(head -n 1 "$PROJ/CLAUDE.md")" = "$(head -n 1 "$TPL/CLAUDE.md.starter")" ]
  [ "$(grep -c '^<!-- >>> agent-config-kit' "$PROJ/CLAUDE.md")" -eq 1 ]
  grep -qx '### FastAPI + LLM service (agent-ai-fastapi)' "$PROJ/CLAUDE.md"
  grep -qx '__pycache__/' "$PROJ/.gitignore"
  run -0 python3 - "$PROJ" "$TPL" <<'PY'
import json, re, sys
root, tpl = sys.argv[1], sys.argv[2]
s = json.load(open(root + "/.claude/settings.json"))
assert "hooks" not in s, sorted(s)
for rule in ("Bash(uv run pytest:*)", "Bash(uv sync:*)"):
    assert rule in s["permissions"]["allow"], rule
assert "Bash(uv run:*)" not in s["permissions"]["allow"], s["permissions"]["allow"]
assert "Bash(docker compose:*)" in s["permissions"]["ask"], s["permissions"]
for rule in ("Edit(SSOT.md)", "Edit(AGENTS.md)"):
    assert rule in s["permissions"]["deny"], rule
lock = json.load(open(root + "/.claude/agent-config-kit.lock"))
me = lock["plugins"]["agent-ai-fastapi"]
version = json.load(open(tpl + "/../../.claude-plugin/plugin.json"))["version"]
assert me["stack"] == "ai-fastapi" and me["version"] == version, me
assert me["answers"] == {"pipeline": "no", "ci-gate": "yes", "pr-templates": "yes", "analytics": "no",
                         "serena-workspace": "no"}, me["answers"]
assert me["kept"] == ["pyproject.toml"], me["kept"]
assert "packageScripts" not in me or me["packageScripts"] == {}, me
held = re.search(r"@0{40}", open(tpl + "/.github/workflows/quality-gate.yml").read())
assert (".github/workflows/quality-gate.yml" in me["files"]) != bool(held), me["files"]
assert "AGENTS.md" in me["seeded"] and "CLAUDE.md" in me["seeded"], me["seeded"]
print("ok")
PY
}

@test "right after setup, sync --check is in sync, even with the pyproject.toml it kept" {
  ai_setup --answer language=python
  run --separate-stderr "$SYNC_BIN" check "${ARGS[@]}"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"kept  pyproject.toml  existed before setup; left alone"* ]] || false
  [[ "${lines[${#lines[@]} - 1]}" == "result: in sync (0 findings; exit 0)" ]] || false
}

@test "a repo without pyproject.toml gets the starter, and sync --check is in sync" {
  git -C "$PROJ" rm -q pyproject.toml
  git -C "$PROJ" commit -q -m "no pyproject"
  ai_setup --answer language=python
  cmp "$PROJ/pyproject.toml" "$TPL/pyproject.toml.starter"
  run -0 --separate-stderr "$SYNC_BIN" check "${ARGS[@]}"
  [[ "$output" == *"seeded  pyproject.toml  created once; the project's own"* ]] || false
}

@test "the installed repo passes agent-core's ai-config check: citations resolve, context in budget" {
  ai_setup --answer language=python
  git -C "$PROJ" add -A
  # shellcheck disable=SC2016 # $1 expands in the child shell
  run -0 --separate-stderr bash -c 'cd "$1" && bash scripts/check/ai-config.sh' _ "$PROJ"
  [[ "$output" == *"All cited rule numbers are defined in AGENTS.md"* ]] || false
  [[ "$output" == *"AI config within budget"* ]] || false
}

@test "the optional answers gate their files: no CI caller or PR templates, the two examples added" {
  ai_setup --answer language=python --answer ci-gate=no --answer pr-templates=no \
    --answer analytics=yes --answer serena-workspace=yes
  [ ! -e "$PROJ/.github/workflows/quality-gate.yml" ]
  [ ! -e "$PROJ/.github/PULL_REQUEST_TEMPLATE" ]
  cmp "$PROJ/.claude/ANALYTICS.example.md" "$TPL/.claude/ANALYTICS.example.md"
  cmp "$PROJ/.claude/SERENA-WORKSPACE.example.md" "$TPL/.claude/SERENA-WORKSPACE.example.md"
  # agent-core's CI workflows are its own, whatever this plugin's answers.
  [ -f "$PROJ/.github/workflows/dependency-review.yml" ]
}

@test "pipeline shape: the example is seeded, and the lock switches the migration guard on" {
  rm -rf "$PROJ"
  make_project pipeline
  ai_args
  local call
  call="$(edit_payload Edit "$PROJ/alembic/versions/0001_initial.py")"
  # Before setup the plugin's hook stays silent: the project has not opted in.
  run_guard "$call" CLAUDE_PLUGIN_ROOT="$PLUGIN"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  ai_setup --answer language=python --answer pipeline=yes
  grep -qE '^  seed +\.claude/examples/pipeline/README\.md ' <<<"$PLAN"
  local f
  for f in README.md pipeline.md alembic.md pipeline-testing.md; do
    cmp "$PROJ/.claude/examples/pipeline/$f" "$TPL/.claude/examples/pipeline/$f"
  done
  run_guard "$call" CLAUDE_PLUGIN_ROOT="$PLUGIN"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"alembic/versions/0001_initial.py is an Alembic revision"* ]] || false
}

@test "the pipeline shape's deleted rules: missing until owned, then no longer checked" {
  ai_setup --answer language=python
  rm "$PROJ/.claude/rules/backend/performance.md"
  printf '\nOur own addition.\n' >>"$PROJ/.claude/rules/backend/fastapi.md"
  run --separate-stderr "$SYNC_BIN" check "${ARGS[@]}"
  [ $((status & 1)) -eq 1 ]
  [[ "$output" == *"missing  .claude/rules/backend/performance.md  setup wrote it; it is gone"* ]] || false
  [[ "$output" == *"modified  .claude/rules/backend/fastapi.md  differs from what setup wrote"* ]] || false
  # sync never touches the edited file; the draft names the two ways out.
  run -0 --separate-stderr "$SYNC_BIN" plan "${ARGS[@]}"
  [[ "$output" == *"agent-sync own .claude/rules/backend/fastapi.md"* ]] || false
  run -0 --separate-stderr "$SYNC_BIN" own "${ARGS[@]}" .claude/rules/backend/performance.md \
    .claude/rules/backend/fastapi.md
  run --separate-stderr "$SYNC_BIN" check "${ARGS[@]}"
  [[ "$output" == *"owned  .claude/rules/backend/fastapi.md"* ]] || false
  [[ "$output" == *"owned  .claude/rules/backend/performance.md"* ]] || false
  [[ "$output" != *"missing  "* ]] || false
  [[ "$output" != *"modified  "* ]] || false
  [ ! -e "$PROJ/.claude/rules/backend/performance.md" ]
  grep -q 'Our own addition.' "$PROJ/.claude/rules/backend/fastapi.md"
}

@test "double wiring: a copied template's migration-guard entry is reported, never removed" {
  mkdir -p "$PROJ/.claude"
  cat >"$PROJ/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [{ "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/migration-guard.sh\"" }]
      }
    ]
  }
}
JSON
  git -C "$PROJ" add -A && git -C "$PROJ" commit -q -m "copied template hooks"
  run -0 --separate-stderr "$SETUP_BIN" plan "${ARGS[@]}" --answer language=python
  grep -qE '^  warn +\.claude/settings\.json +hooks\.PreToolUse\[0\] runs migration-guard\.sh, which agent-ai-fastapi also runs$' <<<"$output"
  ai_setup --answer language=python
  run --separate-stderr "$SYNC_BIN" check "${ARGS[@]}"
  [ $((status & 4)) -eq 4 ]
  [[ "$output" == *"double-wired  .claude/settings.json  hooks.PreToolUse[0] runs migration-guard.sh, which agent-ai-fastapi also runs"* ]] || false
  run -0 python3 -c 'import json, sys; s = json.load(open(sys.argv[1])); print(s["hooks"]["PreToolUse"][0]["hooks"][0]["command"])' \
    "$PROJ/.claude/settings.json"
  [[ "$output" == *".claude/hooks/migration-guard.sh"* ]] || false
}

@test "no clobber: the user's AGENTS.md, .gitleaks.toml and .gitignore lines stay as they were" {
  printf '# Our rules\n' >"$PROJ/AGENTS.md"
  printf '# our gitleaks config\n' >"$PROJ/.gitleaks.toml"
  printf 'our-build-dir/\n' >"$PROJ/.gitignore"
  git -C "$PROJ" add -A && git -C "$PROJ" commit -q -m "our files"
  ai_setup --answer language=python
  [ "$(cat "$PROJ/AGENTS.md")" = "# Our rules" ]
  [ "$(cat "$PROJ/.gitleaks.toml")" = "# our gitleaks config" ]
  [ "$(head -n 1 "$PROJ/.gitignore")" = "our-build-dir/" ]
  [ "$(grep -c '^# >>> agent-config-kit' "$PROJ/.gitignore")" -eq 1 ]
  grep -qE '^  keep +AGENTS\.md ' <<<"$PLAN"
}

@test "a second setup plans nothing, and sync on an unchanged repo writes nothing" {
  ai_setup --answer language=python
  local lock
  lock="$(shasum -a 256 "$PROJ/.claude/agent-config-kit.lock")"
  run -0 --separate-stderr "$SETUP_BIN" plan "${ARGS[@]}"
  [ "$output" = "already set up (agent-ai-fastapi $PLUGIN_VERSION); run /agent-ai-fastapi:sync" ]
  run -0 --separate-stderr "$SYNC_BIN" plan "${ARGS[@]}"
  [[ "$output" == *"(nothing to write)"* ]] || false
  [ "$(shasum -a 256 "$PROJ/.claude/agent-config-kit.lock")" = "$lock" ]
}

@test "a repo already set up with another primary stack is refused" {
  mkdir -p "$PROJ/.claude"
  printf '{"plugins": {"agent-be-hono": {"stack": "be-hono", "version": "1.0.0"}}}\n' \
    >"$PROJ/.claude/agent-config-kit.lock"
  run -3 --separate-stderr "$SETUP_BIN" plan "${ARGS[@]}"
  [[ "$stderr" == *"agent-ai-fastapi conflicts with agent-be-hono"* ]] || false
}
