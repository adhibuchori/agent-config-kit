#!/usr/bin/env bats
# /agent-be-hono:setup and sync end to end, through agent-core's engine, on a toy Bun + Hono +
# Drizzle API: the draft, the write on its digest, what is kept, the managed merges, the hook the
# lock turns on, and sync --check on drift and double wiring. Skipped until agent-core's bin/ is built.

load helpers

setup() {
  [ -x "$CORE/bin/agent-setup" ] && [ -x "$CORE/bin/agent-sync" ] ||
    skip "agent-core's bin/agent-setup and bin/agent-sync are not built yet"
  be_setup_env
  make_api_project
  ANSWERS=(--answer language=typescript --answer ci-gate=yes --answer pr-templates=yes
    --answer analytics=no --answer serena-workspace=no)
}

setup_cli() { "$CORE/bin/agent-setup" "$@" --templates "$TEMPLATES" --stack be-hono --project "$APP"; }
sync_cli() { "$CORE/bin/agent-sync" "$@" --templates "$TEMPLATES" --stack be-hono --project "$APP"; }

plan_digest() {
  setup_cli plan "$@" --json | python3 -c 'import json, sys; print(json.load(sys.stdin)["digest"])'
}

# do_install [--answer id=value ...]: the draft, then apply on its digest (ANSWERS by default).
do_install() {
  local digest
  [ "$#" -gt 0 ] || set -- "${ANSWERS[@]}"
  digest="$(plan_digest "$@")"
  setup_cli apply "$@" --digest "$digest"
}

@test "questions: agent-core's layer first, then this stack's five, each with a recommended choice" {
  run -0 --separate-stderr setup_cli questions --json
  printf '%s' "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
ids = [q["id"] for q in d["questions"]]
assert ids[-5:] == ["ci-gate", "deepseek-review", "pr-templates", "analytics", "serena-workspace"], ids
assert "language" in ids[:-5], ids
assert all(q["recommended"] in q["choices"] for q in d["questions"])
'
}

@test "plan writes nothing, and apply refuses a digest the plan did not print" {
  local before
  before="$(git -C "$APP" status --porcelain)"
  run -0 setup_cli plan "${ANSWERS[@]}"
  [[ "$output" == *"agent-be-hono $PLUGIN_VERSION + agent-core $CORE_VERSION"* ]] || false
  [[ "$output" == *"digest sha256:"* ]] || false
  [ "$(git -C "$APP" status --porcelain)" = "$before" ]
  run -3 setup_cli apply "${ANSWERS[@]}" --digest "sha256:$(printf '0%.0s' {1..64})"
  [ ! -e "$APP/.claude/agent-config-kit.lock" ]
  [ "$(git -C "$APP" status --porcelain)" = "$before" ]
}

@test "apply installs the draft, keeps the user's files and writes the lock" {
  run -0 do_install
  [ -f "$APP/.claude/agent-config-kit.lock" ]
  # The user's CLAUDE.md keeps its lines and gains one managed block with this plugin's part.
  head -3 "$APP/CLAUDE.md" | grep -q '^Our own notes, kept by setup.$'
  grep -q '^### Bun + Hono API (agent-be-hono)$' "$APP/CLAUDE.md"
  [ "$(grep -c '<!-- >>> agent-config-kit' "$APP/CLAUDE.md")" -eq 1 ]
  # Absent starters are created from the plugin's .starter files.
  cmp "$APP/AGENTS.md" "$TPL/AGENTS.md.starter"
  cmp "$APP/SSOT.md" "$TPL/SSOT.md.starter"
  # The backend rules, gates and CI caller, with the scripts' exec bits.
  [ -f "$APP/.claude/rules/backend/drizzle.md" ] && [ -f "$APP/.claude/rules/common/error-codes.md" ]
  [ -x "$APP/scripts/check/migrations.sh" ] && [ -x "$APP/scripts/check/index-coverage.sh" ]
  [ -f "$APP/.github/PULL_REQUEST_TEMPLATE/dev.md" ]
  # The CI caller is installed once a release pins a real commit; until then setup holds it back.
  if grep -Eq '@0{40}' "$TPL/.github/workflows/quality-gate.yml"; then
    [ ! -e "$APP/.github/workflows/quality-gate.yml" ]
  else
    [ -f "$APP/.github/workflows/quality-gate.yml" ]
  fi
  # analytics=no and serena-workspace=no leave their templates out.
  [ ! -e "$APP/.claude/ANALYTICS.example.md" ] && [ ! -e "$APP/.claude/SERENA-WORKSPACE.example.md" ]
  # package.json: the user's lint is kept, the kit's scripts and agent-core's unlock alias are added.
  python3 - "$APP/package.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
s = p["scripts"]
assert s["lint"] == "eslint .", s["lint"]
assert s["dev"] == "bun run --hot src/index.ts"
assert s["unlock"] == "bash scripts/ops/unlock.sh", s.get("unlock")
assert s["db:generate"] == "drizzle-kit generate"
assert s["test:coverage"] == "bun test src --coverage && node scripts/check/coverage-files.mjs"
assert p["dependencies"] == {"drizzle-orm": "0.44.0", "hono": "4.9.0"}
PY
  # The backend permissions were merged into settings, and no hooks key was written.
  python3 - "$APP/.claude/settings.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
assert "Bash(bun test:*)" in s["permissions"]["allow"], s["permissions"]["allow"]
assert "Edit(AGENTS.md)" in s["permissions"]["deny"] and "Read(.env*)" in s["permissions"]["deny"]
assert "hooks" not in s
PY
  # No plugin component lands in the project as a file.
  [ ! -e "$APP/.claude/hooks" ] && [ ! -e "$APP/.claude/commands" ] && [ ! -e "$APP/.claude/agents" ]
  # The .gitignore block holds agent-core's lines and this plugin's: agent state, every real env
  # file, dependencies and build output. The committed .example templates stay visible to git.
  local p
  for p in .claude/state/x .claude/settings.local.json .env .env.local .env.production \
    .env.staging .env.test .env.production.local .envrc node_modules/x dist/x coverage/lcov.info; do
    git -C "$APP" check-ignore -q "$p" || { echo "not ignored: $p" >&2; false; }
  done
  for p in .env.example .env.production.example .env.development.example src/db/migrations/0000_init.sql; do
    ! git -C "$APP" check-ignore -q "$p" || { echo "ignored: $p" >&2; false; }
  done
}

@test "answering no to ci-gate and pr-templates installs neither" {
  run -0 do_install --answer language=typescript --answer ci-gate=no --answer pr-templates=no
  [ ! -e "$APP/.github/workflows/quality-gate.yml" ]
  [ ! -e "$APP/.github/PULL_REQUEST_TEMPLATE" ]
  run -0 sync_cli check
}

@test "the setup lock turns migration-guard on: silent before setup, refusing after" {
  local payload
  payload="$(edit_payload Edit "$APP/src/db/migrations/0000_init.sql")"
  run --separate-stderr env CLAUDE_PROJECT_DIR="$APP" CLAUDE_PLUGIN_ROOT="$PLUGIN" \
    CLAUDE_PLUGIN_DATA="$BATS_TEST_TMPDIR/data" "$HOOK_BASH" "$GUARD" <<<"$payload"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  do_install
  run --separate-stderr env CLAUDE_PROJECT_DIR="$APP" CLAUDE_PLUGIN_ROOT="$PLUGIN" \
    CLAUDE_PLUGIN_DATA="$BATS_TEST_TMPDIR/data" "$HOOK_BASH" "$GUARD" <<<"$payload"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"src/db/migrations/0000_init.sql is drizzle-kit output"* ]]
}

@test "sync --check is clean right after setup, and so is agent-core's own check" {
  do_install
  run -0 sync_cli check
  [[ "$output" == *"in sync"* ]] || false
  run -0 "$CORE/bin/agent-sync" check --templates "$CORE/templates" --stack common --project "$APP"
}

@test "the installed gates pass on the fresh setup: ai-config, coverage-policy, index coverage" {
  do_install
  cd "$APP"
  run -0 --separate-stderr bash scripts/check/ai-config.sh
  run -0 --separate-stderr bash scripts/check/index-coverage.sh
  [[ "$output" == *"Every foreign key column has an index"* ]] || false
  command -v node >/dev/null || skip "node is not installed"
  run -0 --separate-stderr node scripts/check/coverage-policy.mjs
}

@test "every gates.list line the fresh setup can run without node_modules checks something" {
  do_install
  # From the repo root, as gates.sh runs them. The lines that need no installed dependency must not
  # print a skip and pass on nothing.
  cd "$APP"
  run -0 --separate-stderr bash scripts/check/ai-config.sh
  [[ "$output" != *"skipping"* ]] || false
  run -0 --separate-stderr bash scripts/check/double-assertion.sh
  [[ "$output" != *"skipping"* ]] || false
  run grep -cE 'hook-probes\.sh|workflows\.sh' scripts/check/gates.list
  [ "$output" = 0 ]
}

@test "sync --check exits 1 when a managed file is edited, and names it" {
  do_install
  echo "local change" >>"$APP/.claude/rules/backend/drizzle.md"
  run -1 sync_cli check
  [[ "$output" == *"modified"*".claude/rules/backend/drizzle.md"* ]] || false
}

@test "sync --check exits 1 when a kit package script is removed, and sync puts it back" {
  do_install
  python3 - "$APP/package.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
del p["scripts"]["db:generate"]
open(sys.argv[1], "w").write(json.dumps(p, indent=2) + "\n")
PY
  run -1 sync_cli check
  [[ "$output" == *"alias-missing"*"db:generate"* ]] || false
  local digest
  digest="$(sync_cli plan --json | python3 -c 'import json, sys; print(json.load(sys.stdin)["digest"])')"
  run -0 sync_cli apply --digest "$digest"
  run -0 sync_cli check
}

@test "sync --check treats a seeded file's edit as the project's own" {
  do_install
  printf 'code\tbash scripts/check/index-coverage.sh\n' >>"$APP/scripts/check/gates.list"
  echo '[test]' >>"$APP/bunfig.toml"
  run -0 sync_cli check
}

@test "sync --check exits 4 when project settings also wire migration-guard (double wiring)" {
  do_install
  python3 - "$APP/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
s = json.load(open(p))
s["hooks"] = {"PreToolUse": [{"matcher": "Write|Edit", "hooks": [{"type": "command",
    "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/migration-guard.sh\"", "timeout": 10}]}]}
open(p, "w").write(json.dumps(s, indent=2) + "\n")
PY
  run -4 sync_cli check
  [[ "$output" == *"double-wired"*"migration-guard.sh, which agent-be-hono also runs"* ]] || false
}

@test "running setup again plans nothing and points at sync" {
  do_install
  run -0 setup_cli plan "${ANSWERS[@]}"
  [[ "$output" == *"already set up"*"/agent-be-hono:sync"* ]] || false
}

@test "a repo set up with another primary stack plugin is refused" {
  [ -d "$KIT_ROOT/plugins/agent-fe-nextjs/templates/fe-nextjs" ] || skip "agent-fe-nextjs is not built yet"
  local fe=(--templates "$KIT_ROOT/plugins/agent-fe-nextjs/templates" --stack fe-nextjs --project "$APP") digest
  digest="$("$CORE/bin/agent-setup" plan "${fe[@]}" --json | python3 -c 'import json, sys; print(json.load(sys.stdin)["digest"])')"
  run -0 "$CORE/bin/agent-setup" apply "${fe[@]}" --digest "$digest"
  run -3 --separate-stderr setup_cli plan "${ANSWERS[@]}"
  [[ "$stderr" == *"agent-be-hono conflicts with agent-fe-nextjs"* ]] || false
}
