#!/usr/bin/env bats
# /agent-fe-nextjs-static:setup and sync end to end, through agent-core's engine, on the toy site in
# tests/fixtures/fe-nextjs-static: the draft, the write on its digest, what the answers install, what
# is kept, the managed merges, the installed checks running from the project, and sync --check on
# drift, seeded files and double wiring. Skipped until agent-core's bin/ is built.

load helpers

setup() {
  [ -x "$CORE/bin/agent-setup" ] && [ -x "$CORE/bin/agent-sync" ] || skip "agent-core's bin/agent-setup and bin/agent-sync are not built yet"
  make_site
  cd "$BATS_TEST_TMPDIR" || return 1
  # The user's own CLAUDE.md and build script, which setup must keep.
  printf '# Toy Studio\n\nOur own notes, kept by setup.\n' >"$SITE/CLAUDE.md"
  git init -q -b feature/setup "$SITE"
  git -C "$SITE" add -A
  git -C "$SITE" -c user.name=t -c user.email=t@t.invalid commit -q -m fixture
  ANSWERS=(--answer i18n=yes --answer headers=yes --answer lighthouse=no --answer ci-gate=no)
}

setup_cli() { "$CORE/bin/agent-setup" "$@" --templates "$PLUGIN_TEMPLATES" --stack fe-nextjs-static --project "$SITE"; }
sync_cli() { "$CORE/bin/agent-sync" "$@" --templates "$PLUGIN_TEMPLATES" --stack fe-nextjs-static --project "$SITE"; }

do_install() {
  local digest
  digest="$(setup_cli plan "${ANSWERS[@]}" --json | python3 -c 'import json, sys; print(json.load(sys.stdin)["digest"])')"
  setup_cli apply "${ANSWERS[@]}" --digest "$digest"
}

@test "questions lists this stack's six questions after agent-core's, each with a recommended answer" {
  run -0 --separate-stderr setup_cli questions --json
  printf '%s' "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
ids = [q["id"] for q in d["questions"]]
assert ids[-6:] == ["i18n", "headers", "lighthouse", "ci-gate", "react-doctor", "deepseek-review"], ids
assert all(q["recommended"] in q["choices"] and q["why"] for q in d["questions"])
'
}

@test "plan writes nothing, and apply refuses a digest the plan did not print" {
  before="$(git -C "$SITE" status --porcelain)"
  run -0 setup_cli plan "${ANSWERS[@]}"
  [[ "$output" == *"digest sha256:"* ]] || false
  [[ "$output" == *"keep     public/_headers"* ]] || false
  [ "$(git -C "$SITE" status --porcelain)" = "$before" ]
  run -3 setup_cli apply "${ANSWERS[@]}" --digest "sha256:$(printf '0%.0s' {1..64})"
  [ ! -e "$SITE/.claude/agent-config-kit.lock" ]
}

@test "apply installs what the answers ask for, keeps the user's files and writes the lock last" {
  run -0 do_install
  [ -f "$SITE/.claude/agent-config-kit.lock" ]
  # The user's CLAUDE.md keeps every line and gains one managed block with this plugin's part.
  head -3 "$SITE/CLAUDE.md" | grep -q 'Our own notes, kept by setup.'
  grep -q '^### Static site (agent-fe-nextjs-static)$' "$SITE/CLAUDE.md"
  [ "$(grep -c '<!-- >>> agent-config-kit' "$SITE/CLAUDE.md")" -eq 1 ]
  # Absent starters are created; existing seeded files are kept exactly as they were.
  cmp "$SITE/AGENTS.md" "$PLUGIN_TEMPLATES/fe-nextjs-static/AGENTS.md.starter"
  cmp "$SITE/SSOT.md" "$PLUGIN_TEMPLATES/fe-nextjs-static/SSOT.md.starter"
  cmp "$SITE/scripts/check/site.config.json" "$FIXTURE/site/scripts/check/site.config.json"
  cmp "$SITE/public/_headers" "$FIXTURE/site/public/_headers"
  # Answers gate the modules: i18n yes, lighthouse and the CI caller no.
  [ -f "$SITE/.claude/rules/web/i18n.md" ] && [ -f "$SITE/.claude/agent-config.json" ]
  [ ! -e "$SITE/lighthouserc.json" ] && [ ! -e "$SITE/.github/workflows/quality-gate.yaml" ]
  for r in seo static-export security performance responsive design-quality forms-on-static-hosting \
    analytics-consent heavy-hero no-app-machinery; do [ -f "$SITE/.claude/rules/web/$r.md" ]; done
  # package.json: the user's build script is kept; the kit's scripts are added.
  python3 - "$SITE/package.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))["scripts"]
assert s["build"] == "next build", s["build"]
assert s["check:site"] == "node scripts/check/site-audit.mjs"
assert s["check:lighthouse"].startswith("if [ -f lighthouserc.json ]")
assert s["unlock"] == "bash scripts/ops/unlock.sh"
PY
  # Settings: the static permissions are merged, and no hooks key is written.
  python3 - "$SITE/.claude/settings.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
assert "Bash(node scripts/check/site-audit.mjs:*)" in s["permissions"]["allow"]
assert "Edit(public/_headers)" in s["permissions"]["ask"] and "Edit(AGENTS.md)" in s["permissions"]["deny"]
assert "hooks" not in s
PY
  [ ! -e "$SITE/.claude/hooks" ] && [ ! -e "$SITE/.claude/commands" ] && [ ! -e "$SITE/.claude/agents" ]
  grep -qx '.lighthouseci/' "$SITE/.gitignore"
}

@test "the installed checks run from the project, and pass on the toy site's build" {
  do_install
  cd "$SITE"
  run -0 --separate-stderr node scripts/check/site-audit.mjs
  [[ "$output" == *"10 check(s), 0 failed"* ]] || false
  run -0 --separate-stderr node scripts/check/static-export.mjs
  run -0 --separate-stderr node scripts/check/image-budget.mjs --source-only
  run -0 --separate-stderr node scripts/check/font-budget.mjs --source
}

@test "sync --check is clean right after setup, and the installed files pass ai-config.sh" {
  do_install
  run -0 sync_cli check
  [[ "$output" == *"in sync"* ]] || false
  run -0 --separate-stderr bash "$SITE/scripts/check/ai-config.sh"
  [[ "$output" == *"All cited rule numbers are defined in AGENTS.md"* ]] || false
}

@test "sync --check exits 1 when a managed rule or check is edited, and names it" {
  do_install
  echo "local change" >>"$SITE/.claude/rules/web/seo.md"
  echo "// local change" >>"$SITE/scripts/check/metadata.mjs"
  run -1 sync_cli check
  [[ "$output" == *"modified"*".claude/rules/web/seo.md"* ]] || false
  [[ "$output" == *"modified"*"scripts/check/metadata.mjs"* ]] || false
}

@test "sync --check treats edits to seeded files (budgets, gate list, lint config) as the project's own" {
  do_install
  printf 'code\tnode scripts/check/extra.mjs\n' >>"$SITE/scripts/check/gates.list"
  python3 - "$SITE/oxlint.json" <<'PY'
import sys
p = sys.argv[1]
open(p, "w").write(open(p).read().replace('"no-console": "warn"', '"no-console": "off"'))
PY
  echo '# our own note' >>"$SITE/SSOT.md"
  run -0 sync_cli check
}

@test "sync --check exits 4 when project settings also wire a hook agent-core runs (double wiring)" {
  do_install
  python3 - "$SITE/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
s = json.load(open(p))
s["hooks"] = {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command",
    "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/safety-check.sh\"", "timeout": 10}]}]}
json.dump(s, open(p, "w"), indent=2)
PY
  run -4 sync_cli check
  [[ "$output" == *"double-wired"*"safety-check.sh"* ]] || false
}

@test "one primary stack per repo: agent-fe-nextjs refuses a repo set up with this plugin" {
  do_install
  [ -d "$REPO_ROOT/plugins/agent-fe-nextjs/templates/fe-nextjs" ] || skip "agent-fe-nextjs templates are not built"
  run -3 "$CORE/bin/agent-setup" plan --templates "$REPO_ROOT/plugins/agent-fe-nextjs/templates" --stack fe-nextjs --project "$SITE"
  [[ "$output$stderr" == *"agent-fe-nextjs-static"* ]] || false
}

@test "running setup again plans nothing and points at sync" {
  do_install
  run -0 setup_cli plan "${ANSWERS[@]}"
  [[ "$output" == *"/agent-fe-nextjs-static:sync"* ]] || false
}
