#!/usr/bin/env bats
# agent-deploy's layout, read statically: the network lives in two user-run scripts and nowhere
# else, the commands that use it are started by the user only, and setup/sync pass the templates path.

load helpers

@test "the plugin has no hooks, plugin scripts, bin, skills or agents" {
  for dir in hooks scripts bin libexec skills agents; do
    [ ! -e "$DEPLOY_PLUGIN/$dir" ]
  done
  [ "$(cd "$DEPLOY_PLUGIN/commands" && printf '%s ' *)" = "promote-deploy.md setup.md sync.md verify-deploy.md " ]
  [ ! -e "$DEPLOY_PLUGIN/CLAUDE.md" ]
}

@test "network tools appear only in the two scripts a person runs" {
  # Every file setup can install (the _kit folder is the engine's, never installed).
  run -0 grep -rlE 'curl|wget|urllib|http\.client|fetch\(' --exclude-dir=_kit "$DEPLOY_TEMPLATES"
  [ "$(printf '%s\n' "$output" | sort | tr '\n' ' ')" = "$DEPLOY_TEMPLATES/scripts/deploy/trigger-deploy.sh $DEPLOY_TEMPLATES/scripts/deploy/verify-deploy.sh " ]
  run grep -rlE 'npx|bunx|uvx|pipx|pip install|npm install' "$DEPLOY_PLUGIN"
  [ "$status" -eq 1 ]
}

@test "both scripts say they use the network, and only when run" {
  for script in "$VERIFY" "$TRIGGER"; do
    head -12 "$script" | grep -q 'It uses the network, and only when you run it'
  done
}

@test "promote-deploy and verify-deploy are for the user to start, never the model" {
  for cmd in promote-deploy verify-deploy; do
    sed -n '2,/^---$/p' "$DEPLOY_PLUGIN/commands/$cmd.md" | grep -qx 'disable-model-invocation: true'
  done
  # verify-deploy does not pre-approve the script: the permission prompt is the second confirmation.
  run -0 sed -n '/^allowed-tools:/p' "$DEPLOY_PLUGIN/commands/verify-deploy.md"
  assert_lacks "verify-deploy.sh"
}

@test "setup and sync pass the templates path and the stack, and never pre-approve apply" {
  for cmd in setup sync; do
    # shellcheck disable=SC2016 # the literal ${CLAUDE_PLUGIN_ROOT} is the text searched for
    grep -q -- '--templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack deploy' "$DEPLOY_PLUGIN/commands/$cmd.md"
    # shellcheck disable=SC2016 # a literal $, searched for
    run -1 grep -E '\$CLAUDE_PLUGIN_ROOT' "$DEPLOY_PLUGIN/commands/$cmd.md"
    run -0 sed -n '/^allowed-tools:/p' "$DEPLOY_PLUGIN/commands/$cmd.md"
    assert_lacks "apply"
  done
}

@test "templates: exec bits on both scripts, no symlinks, no hooks key, nothing agent-core already ships" {
  [ -x "$VERIFY" ] && [ -x "$TRIGGER" ]
  run -0 find "$DEPLOY_TEMPLATES" -type l -print
  [ -z "$output" ]
  python3 - "$DEPLOY_TEMPLATES" "$CORE/templates/common" <<'PY'
import json, os, sys
mine, core = sys.argv[1], sys.argv[2]
settings = json.load(open(os.path.join(mine, ".claude/settings.json")))
assert set(settings) <= {"$schema", "permissions"}, sorted(settings)
def files(root):
    out = set()
    for folder, dirs, names in os.walk(root):
        dirs[:] = [d for d in dirs if not (folder == root and d == "_kit")]
        out |= {os.path.relpath(os.path.join(folder, n), root) for n in names}
    return out
# Two layers in one setup draft must not ship the same path; settings.json is merged, not shipped.
shared = (files(mine) & files(core)) - {".claude/settings.json"}
assert not shared, sorted(shared)
PY
}

@test "the webhook question gates exactly the trigger script and its ask rules" {
  python3 - "$DEPLOY_TEMPLATES" <<'PY'
import json, os, sys
root = sys.argv[1]
cfg = json.load(open(os.path.join(root, "_kit/setup.json")))
assert cfg["stack"] == "deploy" and [q["id"] for q in cfg["questions"]] == ["webhook"]
q = cfg["questions"][0]
assert q["install"] == {"yes": ["scripts/deploy/trigger-deploy.sh"]}
gated = q["settings"]["yes"]["/permissions/ask"]
ask = json.load(open(os.path.join(root, ".claude/settings.json")))["permissions"]["ask"]
assert set(gated) == {a for a in ask if "trigger-deploy" in a}, (gated, ask)
assert all("verify-deploy" in a or "trigger-deploy" in a for a in ask)
PY
}
