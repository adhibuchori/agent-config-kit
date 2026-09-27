#!/usr/bin/env bats
# /agent-fe-nextjs:setup and sync end to end, through agent-core's engine, on the toy app in
# tests/fixtures/fe-nextjs: the draft, the write on its digest, what is kept, the managed merges,
# and sync --check on drift and double wiring. Skipped until agent-core's bin/ is built.

load helpers

setup() {
  [ -x "$CORE/bin/agent-setup" ] && [ -x "$CORE/bin/agent-sync" ] || skip "agent-core's bin/agent-setup and bin/agent-sync are not built yet"
  APP="$BATS_TEST_TMPDIR/app"
  mkdir -p "$APP"
  cp -R "$FIXTURE"/. "$APP"/
  mv "$APP/CLAUDE.md.fixture" "$APP/CLAUDE.md"
  git init -q -b feature/setup "$APP"
  git -C "$APP" add -A
  git -C "$APP" -c user.name=t -c user.email=t@t.invalid commit -q -m fixture
  ANSWERS=(--answer i18n=yes --answer dialogs=no --answer responsive=yes --answer skeletons=no
    --answer react-doctor-ci=no --answer design-docs=no)
}

setup_cli() { "$CORE/bin/agent-setup" "$@" --templates "$TEMPLATES" --stack fe-nextjs --project "$APP"; }
sync_cli() { "$CORE/bin/agent-sync" "$@" --templates "$TEMPLATES" --stack fe-nextjs --project "$APP"; }

plan_digest() {
  setup_cli plan "${ANSWERS[@]}" --json | python3 -c 'import json, sys; print(json.load(sys.stdin)["digest"])'
}

do_install() {
  local digest
  digest="$(plan_digest)"
  setup_cli apply "${ANSWERS[@]}" --digest "$digest"
}

@test "questions lists this stack's six questions with a recommended answer each" {
  run -0 --separate-stderr setup_cli questions --json
  printf '%s' "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
ids = [q["id"] for q in d["questions"]]
for want in ("i18n", "dialogs", "responsive", "skeletons", "react-doctor-ci", "design-docs"):
    assert want in ids, (want, ids)
q = {q["id"]: q for q in d["questions"]}
assert all(q[i]["recommended"] in q[i]["choices"] for i in q)
'
}

@test "plan writes nothing, and apply refuses a digest the plan did not print" {
  before="$(git -C "$APP" status --porcelain)"
  run -0 setup_cli plan "${ANSWERS[@]}"
  [[ "$output" == *"digest sha256:"* ]] || false
  [ "$(git -C "$APP" status --porcelain)" = "$before" ]
  run -3 setup_cli apply "${ANSWERS[@]}" --digest "sha256:$(printf '0%.0s' {1..64})"
  [ ! -e "$APP/.claude/agent-config-kit.lock" ]
}

@test "apply installs the draft, keeps the user's files and writes the lock last" {
  run -0 do_install
  [ -f "$APP/.claude/agent-config-kit.lock" ]
  # The user's CLAUDE.md keeps every line, and gains one managed block holding this plugin's part.
  head -3 "$APP/CLAUDE.md" | cmp - <(head -3 "$FIXTURE/CLAUDE.md.fixture")
  grep -q '^### Next.js app (agent-fe-nextjs)$' "$APP/CLAUDE.md"
  [ "$(grep -c '<!-- >>> agent-config-kit' "$APP/CLAUDE.md")" -eq 1 ]
  # Absent starters are created from the plugin's .starter files.
  cmp "$APP/AGENTS.md" "$STACK_DIR/AGENTS.md.starter"
  cmp "$APP/SSOT.md" "$STACK_DIR/SSOT.md.starter"
  # Answers gate the optional modules.
  [ -f "$APP/scripts/check/i18n.ts" ] && [ -f "$APP/scripts/check/responsive.ts" ]
  [ ! -e "$APP/scripts/check/dialog-desc.ts" ] && [ ! -e "$APP/.claude/rules/web/skeletons.md" ]
  [ ! -e "$APP/.github/workflows/react-doctor.yml" ] && [ ! -e "$APP/PRODUCT.example.md" ]
  # package.json: the user's lint script is kept; missing scripts are added.
  python3 - "$APP/package.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))["scripts"]
assert s["lint"] == "next lint", s["lint"]
assert s["check:i18n"].startswith("if [ -f scripts/check/i18n.ts ]"), s["check:i18n"]
assert "type-check" in s and "check:soc" in s
assert s["unlock"] == "bash scripts/ops/unlock.sh", s.get("unlock")
PY
  # The managed .gitignore block ignores real env files and keeps the committed examples tracked.
  for f in .env .env.local .env.development .env.production .env.staging.local .next/x next-env.d.ts; do
    git -C "$APP" check-ignore -q "$f"
  done
  for f in .env.development.example .env.production.example; do
    ! git -C "$APP" check-ignore -q "$f" || false
  done
  [ -f "$APP/.env.development.example" ]
  # The fe permissions were merged into settings, and no hooks key was written.
  python3 - "$APP/.claude/settings.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
assert "Bash(bun run check:*)" in s["permissions"]["allow"] and "Edit(AGENTS.md)" in s["permissions"]["deny"]
assert "Bash(bun run:*)" not in s["permissions"]["allow"], s["permissions"]["allow"]
assert "hooks" not in s
PY
  # No kit file lands under a plugin-component folder in the project.
  [ ! -e "$APP/.claude/hooks" ] && [ ! -e "$APP/.claude/commands" ]
}

@test "sync --check is clean right after setup, and the installed rules pass ai-config.sh" {
  do_install
  run -0 sync_cli check
  [ -f "$APP/scripts/check/ai-config.sh" ] || skip "agent-core does not install ai-config.sh"
  run -0 --separate-stderr bash "$APP/scripts/check/ai-config.sh"
}

@test "agent-core's own sync --check stays clean after this plugin's setup" {
  # It renders this plugin's .gitignore lines from the lock rather than from these templates.
  do_install
  run -0 "$CORE/bin/agent-sync" check --templates "$CORE/templates" --stack common --project "$APP"
  [[ "$output" != *"block-"* ]] || false
}

@test "sync --check exits 1 when a managed file is edited, and names it" {
  do_install
  echo "local change" >>"$APP/.claude/rules/web/testing.md"
  run -1 sync_cli check
  [[ "$output" == *"modified"*".claude/rules/web/testing.md"* ]] || false
}

@test "sync --check reports a seeded file's edit as nothing: it is the project's" {
  do_install
  printf 'code\tbun run check:extra\n' >>"$APP/scripts/check/gates.list"
  run -0 sync_cli check
}

@test "sync --check exits 4 when project settings wire generated-guard too (double wiring)" {
  do_install
  python3 - "$APP/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
s = json.load(open(p))
s["hooks"] = {"PreToolUse": [{"matcher": "Write|Edit", "hooks": [{"type": "command",
    "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/generated-guard.sh\"", "timeout": 10}]}]}
json.dump(s, open(p, "w"), indent=2)
PY
  run -4 sync_cli check
  [[ "$output" == *"double-wired"*"generated-guard.sh"* ]] || false
}

@test "running setup again plans nothing and points at sync" {
  do_install
  run -0 setup_cli plan "${ANSWERS[@]}"
  [[ "$output" == *"/agent-fe-nextjs:sync"* ]] || false
}
