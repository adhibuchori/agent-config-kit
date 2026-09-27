#!/usr/bin/env bats
# agent-fe-threejs's layout and templates, read statically: nothing vendored, commands that pass the
# templates path, a rule whose frontmatter loads, and a budget config that says what the rule says.

load helpers

@test "the plugin has no hooks, scripts, bin, skills or agents: commands and templates only" {
  for dir in hooks scripts bin libexec skills agents; do
    [ ! -e "$PLUGIN/$dir" ]
  done
  [ "$(cd "$PLUGIN/commands" && printf '%s ' *)" = "setup.md sync.md " ]
  [ ! -e "$PLUGIN/CLAUDE.md" ]
}

@test "no third-party skill is vendored: no skill tree, no lock, no skill files in the templates" {
  run -0 find "$TPL" \( -path '*/.claude/skills*' -o -path '*/.agents/*' -o -name 'skills-lock.json' -o -name 'SKILL.md' \) -print
  [ -z "$output" ]
}

@test "every template file is plain: no symlinks, no hooks key, only the settings keys the engine allows" {
  run -0 find "$TPL" -type l -print
  [ -z "$output" ]
  python3 - "$TPL/.claude/settings.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
assert set(s) <= {"$schema", "permissions", "sandbox", "env", "extraKnownMarketplaces", "enabledPlugins"}, sorted(s)
PY
}

@test "commands pass the templates path and the stack, and never pre-approve apply" {
  for cmd in setup sync; do
    # shellcheck disable=SC2016 # the literal ${CLAUDE_PLUGIN_ROOT} is the text searched for
    grep -q -- '--templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack fe-threejs' "$PLUGIN/commands/$cmd.md"
    # Never the bare form: only ${CLAUDE_PLUGIN_ROOT} is substituted inline in command markdown.
    # shellcheck disable=SC2016 # a literal $, searched for
    run -1 grep -E '\$CLAUDE_PLUGIN_ROOT' "$PLUGIN/commands/$cmd.md"
    run -0 sed -n '/^allowed-tools:/p' "$PLUGIN/commands/$cmd.md"
    assert_lacks "apply"
  done
}

@test "the rule's frontmatter is a quoted paths list (a bare leading * is a YAML alias)" {
  python3 - "$TPL/.claude/rules/web/3d.md" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.match(r"---\n(.*?)\n---\n", text, re.S)
assert m, "no frontmatter"
lines = m.group(1).splitlines()
assert lines[0] == "paths:", lines[0]
assert len(lines) > 5 and all(re.fullmatch(r"  - '[^']+'", l) for l in lines[1:]), lines
for n in range(1, 6):
    assert f"## {n}. " in text, f"section {n} missing"
PY
}

@test "the budget config's defaults are the numbers the rule states" {
  python3 - "$TPL/scripts/check/3d-budget.json" "$TPL/.claude/rules/web/3d.md" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1]))
rule = " ".join(open(sys.argv[2], encoding="utf-8").read().split())
b = cfg["budgets"]
assert b == {"modelKB": 1536, "triangles": 100000, "textureKB": 512, "texturePx": 2048, "environmentKB": 2048}, b
for phrase in ("a model 1.5 MB", "100,000 triangles as rendered", "a texture 512 KB and 2048 px", "environment map 2 MB"):
    assert phrase in rule, phrase
assert cfg["roots"] == ["public"] and cfg["exceptions"] == []
PY
}

@test "setup.json seeds the budget config and prints the two by-hand snippets" {
  python3 - "$TPL/_kit" <<'PY'
import json, os, sys
kit = sys.argv[1]
cfg = json.load(open(os.path.join(kit, "setup.json")))
assert cfg["stack"] == "fe-threejs" and cfg["questions"] == [] and cfg["packageScripts"] == {}
assert cfg["seed"] == ["scripts/check/3d-budget.json"]
assert cfg["snippets"] == {".claude/settings.json": "snippets/skill-overrides.json",
                           "scripts/check/gates.list": "snippets/gates.list"}
overrides = json.load(open(os.path.join(kit, "snippets/skill-overrides.json")))
assert list(overrides) == ["skillOverrides"]
assert set(overrides["skillOverrides"].values()) <= {"on", "name-only", "user-invocable-only", "off"}
lines = [l for l in open(os.path.join(kit, "snippets/gates.list")) if l.strip() and not l.startswith("#")]
assert lines == ["code\tnode scripts/check/3d-budget.mjs\n"], lines
PY
}

@test "the skills guide pins the installer, turns its telemetry off and targets Claude Code only" {
  local guide="$TPL/docs/3d-skills.md"
  run -0 grep -o 'npx skills[@0-9.]*' "$guide"
  [ "$(printf '%s\n' "$output" | sort -u)" = "npx skills@1.7.0" ]
  run -0 grep 'npx skills@1.7.0 \(add\|update\)' "$guide"
  [ "$(printf '%s\n' "$output" | grep -vc 'DO_NOT_TRACK=1')" -eq 0 ]
  run -0 grep 'npx skills@1.7.0 add' "$guide"
  [ "$(printf '%s\n' "$output" | grep -vc -- '--agent claude-code')" -eq 0 ]
  # The skills-lock.json example is valid JSON with the installer's version-1 shape.
  python3 - "$guide" <<'PY'
import json, re, sys
text = open(sys.argv[1], encoding="utf-8").read()
blocks = [json.loads(b) for b in re.findall(r"```json\n(.*?)```", text, re.S)]
lock = next(b for b in blocks if "version" in b)
assert lock["version"] == 1
entry = next(iter(lock["skills"].values()))
assert list(entry) == ["source", "ref", "sourceType", "skillPath", "computedHash"], list(entry)
PY
}

@test "npx appears only in the skills guide, and the budget check touches no network" {
  run -0 grep -rln 'npx' "$PLUGIN"
  [ "$output" = "$TPL/docs/3d-skills.md" ]
  run -0 grep -E '^import' "$TPL/scripts/check/3d-budget.mjs"
  [ "$(printf '%s\n' "$output" | grep -o "from 'node:[a-z]*'" | sort -u | tr '\n' ' ')" = "from 'node:fs' from 'node:path' from 'node:url' " ]
  run grep -nE 'fetch\(|https?\.request|child_process|node:net|node:http' "$TPL/scripts/check/3d-budget.mjs"
  [ "$status" -eq 1 ]
}
