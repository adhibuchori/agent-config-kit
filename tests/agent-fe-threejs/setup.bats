#!/usr/bin/env bats
# /agent-fe-threejs:setup and sync end to end, through agent-core's engine, on a toy Next.js site with
# a three.js scene: the draft, the write on its digest, the managed merges, the seeded budget config,
# the by-hand lines, drift, and installing next to agent-fe-nextjs. Skipped until agent-core's bin/ exists.

load helpers

setup() {
  [ -x "$CORE/bin/agent-setup" ] && [ -x "$CORE/bin/agent-sync" ] ||
    skip "agent-core's bin/agent-setup and bin/agent-sync are not built yet"
  tj_env
  APP="$BATS_TEST_TMPDIR/site"
  mkdir -p "$APP/public/models" "$APP/app"
  cat >"$APP/package.json" <<'JSON'
{
  "name": "toy-site",
  "private": true,
  "scripts": { "build": "next build" },
  "dependencies": { "next": "16.0.0", "react": "19.2.0", "three": "0.180.0", "@react-three/fiber": "9.3.0" }
}
JSON
  printf '# Toy site\n\nOur own notes, kept by setup.\n' >"$APP/CLAUDE.md"
  printf 'export default function Page() { return null; }\n' >"$APP/app/page.tsx"
  python3 "$MAKE" "$APP/public/models/hero.glb" '{"kind": "glb", "meshes": [[{"count": 3000}]]}'
  git -C "$APP" init -q
  git -C "$APP" add -A
  git -C "$APP" commit -q -m init
  APP="$(cd "$APP" && pwd -P)"
}

setup_cli() { "$CORE/bin/agent-setup" "$@" --templates "$TEMPLATES" --stack fe-threejs --project "$APP"; }
sync_cli() { "$CORE/bin/agent-sync" "$@" --templates "$TEMPLATES" --stack fe-threejs --project "$APP"; }

# do_install: the draft, then apply on its digest (recommended answers throughout).
do_install() {
  local digest
  digest="$(setup_cli plan --json | python3 -c 'import json, sys; print(json.load(sys.stdin)["digest"])')"
  setup_cli apply --digest "$digest"
}

@test "questions: this add-on asks none of its own; only agent-core's layer asks" {
  run -0 --separate-stderr setup_cli questions --json
  printf '%s' "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
core = json.load(open(sys.argv[1]))["questions"]
assert [q["id"] for q in d["questions"]] == [q["id"] for q in core], d
' "$CORE/templates/common/_kit/setup.json"
}

@test "plan writes nothing and shows the seeded config and both by-hand lines" {
  local before
  before="$(git -C "$APP" status --porcelain)"
  run -0 setup_cli plan
  assert_has "agent-fe-threejs 1.0.0 + agent-core $CORE_VERSION"
  assert_has "  create   .claude/rules/web/3d.md"
  assert_has "  create   scripts/check/3d-budget.mjs"
  assert_has "  create   docs/3d-skills.md"
  assert_has "  seed     scripts/check/3d-budget.json"
  assert_has "  by-hand  scripts/check/gates.list"
  assert_has "  by-hand  .claude/settings.json"
  assert_has "_kit/snippets/skill-overrides.json holds"
  [ "$(git -C "$APP" status --porcelain)" = "$before" ]
}

@test "apply installs the draft, keeps the user's CLAUDE.md, and the budget check runs" {
  run -0 do_install
  [ -f "$APP/.claude/agent-config-kit.lock" ]
  cmp "$APP/.claude/rules/web/3d.md" "$TPL/.claude/rules/web/3d.md"
  cmp "$APP/scripts/check/3d-budget.mjs" "$TPL/scripts/check/3d-budget.mjs"
  cmp "$APP/scripts/check/3d-budget.json" "$TPL/scripts/check/3d-budget.json"
  cmp "$APP/docs/3d-skills.md" "$TPL/docs/3d-skills.md"
  [ ! -e "$APP/_kit" ] && [ ! -e "$APP/.claude/skills" ] && [ ! -e "$APP/skills-lock.json" ]
  head -3 "$APP/CLAUDE.md" | grep -q '^Our own notes, kept by setup.$'
  grep -q '^### 3D scenes (agent-fe-threejs)$' "$APP/CLAUDE.md"
  python3 - "$APP/.claude/settings.json" <<'PY'
import json, sys
allow = json.load(open(sys.argv[1]))["permissions"]["allow"]
assert "Bash(node scripts/check/3d-budget.mjs:*)" in allow, allow
assert "skillOverrides" not in json.load(open(sys.argv[1]))
PY
  command -v node >/dev/null 2>&1 || skip "node is not installed"
  # shellcheck disable=SC2016 # $1 belongs to the inner shell
  run -0 bash -c 'cd "$1" && node scripts/check/3d-budget.mjs' _ "$APP"
  assert_has "3d-budget: 1 model, 0 textures, 0 environment maps under public; 0 over budget"
}

@test "sync --check: in sync after setup; an edited rule is drift until it is owned" {
  do_install
  run -0 sync_cli check
  assert_has "seeded  scripts/check/3d-budget.json"
  printf "  - 'src/visuals/**'\n" >>"$APP/.claude/rules/web/3d.md"
  run -1 sync_cli check
  assert_has "modified  .claude/rules/web/3d.md"
  run -0 sync_cli own .claude/rules/web/3d.md
  run -0 sync_cli check
  assert_has "owned  .claude/rules/web/3d.md"
}

@test "sync --check: the seeded budget config is the repo's to edit" {
  do_install
  python3 - "$APP/scripts/check/3d-budget.json" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1]))
cfg["budgets"]["triangles"] = 50000
json.dump(cfg, open(sys.argv[1], "w"), indent=2)
PY
  run -0 sync_cli check
}

@test "sync --check: a removed allow rule and a deleted check script are drift" {
  do_install
  rm "$APP/scripts/check/3d-budget.mjs"
  python3 - "$APP/.claude/settings.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
s["permissions"]["allow"].remove("Bash(node scripts/check/3d-budget.mjs:*)")
json.dump(s, open(sys.argv[1], "w"), indent=2)
PY
  run -1 sync_cli check
  assert_has "missing  scripts/check/3d-budget.mjs"
  assert_has "settings-missing  .claude/settings.json"
}

@test "setup a second time plans nothing and points at sync" {
  do_install
  run -0 setup_cli plan
  assert_has "already set up"
  assert_has "/agent-fe-threejs:sync"
}

@test "installs next to agent-fe-nextjs: one lock, both in sync" {
  local fe="$KIT_ROOT/plugins/agent-fe-nextjs/templates" digest
  [ -f "$fe/fe-nextjs/_kit/setup.json" ] || skip "agent-fe-nextjs has no templates yet"
  digest="$("$CORE/bin/agent-setup" plan --templates "$fe" --stack fe-nextjs --project "$APP" --json |
    python3 -c 'import json, sys; print(json.load(sys.stdin)["digest"])')"
  "$CORE/bin/agent-setup" apply --templates "$fe" --stack fe-nextjs --project "$APP" --digest "$digest" >/dev/null
  run -0 do_install
  python3 - "$APP/.claude/agent-config-kit.lock" <<'PY'
import json, sys
plugins = json.load(open(sys.argv[1]))["plugins"]
assert {"agent-core", "agent-fe-nextjs", "agent-fe-threejs"} <= set(plugins), sorted(plugins)
PY
  grep -q '^### 3D scenes (agent-fe-threejs)$' "$APP/CLAUDE.md"
  [ "$(grep -c '<!-- >>> agent-config-kit' "$APP/CLAUDE.md")" -eq 1 ]
  run -0 sync_cli check
  run -0 "$CORE/bin/agent-sync" check --templates "$fe" --stack fe-nextjs --project "$APP"
}
