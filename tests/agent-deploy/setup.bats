#!/usr/bin/env bats
# /agent-deploy:setup and sync end to end, through agent-core's engine, on a toy repo: the webhook
# question, the ask-first permissions for the network scripts, exec bits, drift and a second run.
# Skipped until agent-core's bin/ exists. No test here touches the network.

load helpers

setup() {
  [ -x "$CORE/bin/agent-setup" ] && [ -x "$CORE/bin/agent-sync" ] ||
    skip "agent-core's bin/agent-setup and bin/agent-sync are not built yet"
  unset CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  export TMPDIR="$BATS_TEST_TMPDIR"
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig" GIT_CONFIG_NOSYSTEM=1
  printf '[user]\n\temail = test@example.invalid\n\tname = test\n[init]\n\tdefaultBranch = main\n' >"$GIT_CONFIG_GLOBAL"
  APP="$BATS_TEST_TMPDIR/app"
  mkdir -p "$APP"
  printf '# Toy app\n\nOur own notes, kept by setup.\n' >"$APP/CLAUDE.md"
  git -C "$APP" init -q
  git -C "$APP" add -A
  git -C "$APP" commit -q -m init
  APP="$(cd "$APP" && pwd -P)"
  TEMPLATES="$DEPLOY_PLUGIN/templates"
}

setup_cli() { "$CORE/bin/agent-setup" "$@" --templates "$TEMPLATES" --stack deploy --project "$APP"; }
sync_cli() { "$CORE/bin/agent-sync" "$@" --templates "$TEMPLATES" --stack deploy --project "$APP"; }

# do_install [--answer id=value ...]: the draft, then apply on its digest.
do_install() {
  local digest
  digest="$(setup_cli plan "$@" --json | python3 -c 'import json, sys; print(json.load(sys.stdin)["digest"])')"
  setup_cli apply "$@" --digest "$digest"
}

ask_rules() {
  python3 -c 'import json, sys; print("\n".join(json.load(open(sys.argv[1]))["permissions"].get("ask", [])))' \
    "$APP/.claude/settings.json"
}

@test "questions: agent-core's layer first, then webhook, deploy-on-merge and strip-ai, each recommended no" {
  run -0 --separate-stderr setup_cli questions --json
  printf '%s' "$output" | python3 -c '
import json, sys
qs = json.load(sys.stdin)["questions"]
assert [q["id"] for q in qs[-3:]] == ["webhook", "deploy-on-merge", "strip-ai"], qs[-3:]
assert all(q["recommended"] == "no" for q in qs[-3:]), qs[-3:]
assert "language" in [q["id"] for q in qs[:-3]]
'
}

@test "webhook=no: the smoke script with its exec bit and ask rules; no trigger script" {
  run -0 do_install --answer webhook=no
  [ -x "$APP/scripts/deploy/verify-deploy.sh" ]
  cmp "$APP/scripts/deploy/verify-deploy.sh" "$DEPLOY_TEMPLATES/scripts/deploy/verify-deploy.sh"
  [ ! -e "$APP/scripts/deploy/trigger-deploy.sh" ]
  run -0 ask_rules
  assert_has "Bash(bash scripts/deploy/verify-deploy.sh:*)"
  assert_has "Bash(./scripts/deploy/verify-deploy.sh:*)"
  assert_lacks "trigger-deploy"
  head -3 "$APP/CLAUDE.md" | grep -q '^Our own notes, kept by setup.$'
  grep -q '^### Deploys (agent-deploy)$' "$APP/CLAUDE.md"
  # agent-core's layer brings the deploy-platform MCP example; agent-deploy does not ship a second copy.
  [ -f "$APP/.claude/mcp/deploy-platform.example.json" ]
  run -0 sync_cli check
}

@test "webhook=yes: the trigger script too, and Claude must ask before running it" {
  run -0 do_install --answer webhook=yes
  [ -x "$APP/scripts/deploy/trigger-deploy.sh" ]
  run -0 ask_rules
  assert_has "Bash(bash scripts/deploy/trigger-deploy.sh:*)"
  assert_has "Bash(scripts/deploy/trigger-deploy.sh:*)"
  run -0 sync_cli check
}

@test "the installed scripts start without the network: --help, and no ref" {
  do_install --answer webhook=yes
  run -0 "$RUN_BASH" "$APP/scripts/deploy/verify-deploy.sh" --help
  assert_has "Checks (each prints PASS, FAIL, WARN or SKIP):"
  run -2 env -u DEPLOY_REF DEPLOY_WEBHOOK_URL=https://127.0.0.1:9/x "$RUN_BASH" "$APP/scripts/deploy/trigger-deploy.sh"
}

@test "sync --check: an edited script, a lost exec bit or a removed ask rule is drift" {
  do_install --answer webhook=yes
  printf '# local tweak\n' >>"$APP/scripts/deploy/trigger-deploy.sh"
  chmod -x "$APP/scripts/deploy/verify-deploy.sh"
  python3 - "$APP/.claude/settings.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
s["permissions"]["ask"].remove("Bash(bash scripts/deploy/verify-deploy.sh:*)")
json.dump(s, open(sys.argv[1], "w"), indent=2)
PY
  run -1 sync_cli check
  assert_has "modified  scripts/deploy/trigger-deploy.sh"
  assert_has "mode  scripts/deploy/verify-deploy.sh"
  assert_has "settings-missing  .claude/settings.json"
}

@test "sync plan restores the exec bit and the ask rule, and leaves an edited file alone" {
  do_install --answer webhook=yes
  printf '# local tweak\n' >>"$APP/scripts/deploy/trigger-deploy.sh"
  chmod -x "$APP/scripts/deploy/verify-deploy.sh"
  local digest
  digest="$(sync_cli plan --json | python3 -c 'import json, sys; print(json.load(sys.stdin)["digest"])')"
  run -0 sync_cli apply --digest "$digest"
  [ -x "$APP/scripts/deploy/verify-deploy.sh" ]
  tail -1 "$APP/scripts/deploy/trigger-deploy.sh" | grep -q '^# local tweak$'
  run -1 sync_cli check
  assert_has "modified  scripts/deploy/trigger-deploy.sh"
  assert_lacks "mode  "
}

@test "setup a second time plans nothing and points at sync" {
  do_install --answer webhook=no
  run -0 setup_cli plan
  assert_has "already set up"
  assert_has "/agent-deploy:sync"
}
