#!/usr/bin/env bats
# The ios-swiftui template as files: setup.json's shape, the rule index and what it points at, the
# shared copies, the pins, and the seeded Swift within the kit's own limits. Read-only.

load helpers

setup() {
  ios_setup_env
}

@test "_kit/setup.json: known keys, every other primary stack a conflict, globs that match files" {
  run -0 python3 - "$TPL" <<'PY'
import fnmatch, json, os, re, sys
tpl = sys.argv[1]
cfg = json.load(open(os.path.join(tpl, "_kit/setup.json")))
assert set(cfg) <= {"stack", "conflictsWith", "questions", "seed", "snippets", "gitignore", "packageScripts"}, set(cfg)
assert cfg["stack"] == "ios-swiftui"
assert sorted(cfg["conflictsWith"]) == ["agent-ai-fastapi", "agent-be-axum", "agent-be-go", "agent-be-hono",
                                        "agent-docs-nextra", "agent-fe-nextjs", "agent-fe-nextjs-static"], cfg["conflictsWith"]
assert cfg["packageScripts"] == {} and cfg["snippets"] == {}
ids = [q["id"] for q in cfg["questions"]]
assert len(ids) == len(set(ids)) and ids[-1] == "payload-encryption", ids
files = []
for d, _, fs in os.walk(tpl):
    for f in fs:
        rel = os.path.relpath(os.path.join(d, f), tpl)
        if not rel.startswith("_kit/"):
            files.append(rel[:-8] if rel.endswith(".starter") else rel)
def glob_re(g):
    out, i = "", 0
    while i < len(g):
        if g.startswith("**/", i): out, i = out + "(?:.*/)?", i + 3
        elif g.startswith("**", i): out, i = out + ".*", i + 2
        else:
            c = g[i]; out += "[^/]*" if c == "*" else "[^/]" if c == "?" else re.escape(c); i += 1
    return re.compile(out + r"\Z")
globs = list(cfg["seed"]) + [g for q in cfg["questions"] for gs in q.get("install", {}).values() for g in gs]
for g in globs:
    assert any(glob_re(g).match(f) for f in files), f"{g} matches no template file"
print("ok")
PY
}

@test "every script gates.list runs is installed by this plugin or by agent-core, the payload check among them" {
  local kinds cmd script
  while IFS=$'\t' read -r kinds cmd; do
    case "$kinds" in '' | '#'*) continue ;; esac
    [ -n "$cmd" ]
    script="$(grep -oE 'scripts/check/[A-Za-z0-9_.-]+' <<<"$cmd" | tail -1 || true)"
    [ -z "$script" ] || [ -f "$TPL/$script" ] || [ -f "$CORE_TPL/$script" ] || {
      echo "gates.list runs $script, which nothing installs" >&2
      return 1
    }
  done <"$TPL/scripts/check/gates.list"
  grep -qxF "$(printf 'code\tnode scripts/check/payload-registry.mjs')" "$TPL/scripts/check/gates.list"
}

@test "the shared check scripts are byte copies of the other stacks'" {
  cmp "$TPL/scripts/check/ci-env.sh" "$KIT_ROOT/plugins/agent-be-hono/templates/be-hono/scripts/check/ci-env.sh"
  cmp "$TPL/scripts/check/coverage-policy.mjs" "$KIT_ROOT/plugins/agent-be-hono/templates/be-hono/scripts/check/coverage-policy.mjs"
  local other
  for other in agent-be-go/templates/be-go agent-be-axum/templates/be-axum; do
    [ -f "$KIT_ROOT/plugins/$other/scripts/check/coverage-per-file.mjs" ] || continue
    cmp "$TPL/scripts/check/coverage-per-file.mjs" "$KIT_ROOT/plugins/$other/scripts/check/coverage-per-file.mjs"
  done
}

@test "the payload files every stack shares are byte copies, and the registry scripts the new stacks' own" {
  local f other
  for f in .claude/PAYLOAD-CONTRACT.md .claude/rules/common/payload-contract.md scripts/check/payload-vectors.json; do
    cmp "$TPL/$f" "$KIT_ROOT/plugins/agent-fe-nextjs/templates/fe-nextjs/$f"
  done
  for f in lib generate check; do
    [ -f "$TPL/scripts/$f/payload-registry.mjs" ]
    for other in agent-be-go/templates/be-go agent-be-axum/templates/be-axum; do
      [ -f "$KIT_ROOT/plugins/$other/scripts/$f/payload-registry.mjs" ] || continue
      cmp "$TPL/scripts/$f/payload-registry.mjs" "$KIT_ROOT/plugins/$other/scripts/$f/payload-registry.mjs"
    done
  done
}

@test "payload-encryption installs the app's half only with yes; the registry scripts come with every answer" {
  run -0 python3 - "$TPL" <<'PY'
import json, os, sys
tpl = sys.argv[1]
cfg = json.load(open(os.path.join(tpl, "_kit/setup.json")))
q = next(q for q in cfg["questions"] if q["id"] == "payload-encryption")
assert q["choices"] == ["yes", "no"] and q["recommended"] == "no", q
yes = q["install"]["yes"]
for path in (".claude/PAYLOAD-CONTRACT.md", ".claude/rules/common/payload-contract.md", ".claude/rules/ios/payload.md",
             "payload.config.json", "scripts/check/payload-vectors.json",
             "Packages/AppCore/Sources/APIClient/Payload*.swift", "Packages/AppCore/Tests/APIClientTests/Payload*.swift"):
    assert path in yes, path
assert not any("payload-registry" in g for g in yes), yes
for seeded in ("payload.config.json", "Packages/AppCore/Sources/APIClient/Payload*.swift",
               "Packages/AppCore/Tests/APIClientTests/Payload*.swift"):
    assert seeded in cfg["seed"], seeded
config = json.load(open(os.path.join(tpl, "payload.config.json")))
assert config["encryption"] == "strict" and config["language"] == "swift", config
assert config["registry"] == "Packages/AppCore/Sources/APIClient/PayloadEndpoints.generated.swift", config
assert config["spec"] == "Packages/AppCore/Sources/APIClient/openapi.json", config
assert config["handshake"] == "getPayloadHandshake", config
assert config["exemptions"]["GET /api/payload/handshake"]["encryption"] == "none", config
print("ok")
PY
}

@test "the generated payload registry is out of SwiftLint, swift-format, the coverage floor and hand edits" {
  grep -qF -- '- Packages/*/Sources/*/*.generated.swift' "$TPL/.swiftlint.yml"
  grep -qx '\*.generated.swift' "$TPL/.swift-format-ignore"
  grep -qE '^Packages/AppCore/Sources/APIClient/\*\.generated\.swift +# generated: ' "$TPL/scripts/check/coverage-exempt.txt"
  run jq -r '.generatedPaths[]' "$TPL/.claude/agent-config.json"
  grep -qx 'Packages/AppCore/Sources/APIClient/PayloadEndpoints.generated.swift' <<<"$output"
}

@test "the payload types stay internal: only the session's initialisers and the error mapper are package" {
  run -0 python3 - "$TPL/Packages/AppCore/Sources/APIClient" <<'PY'
import glob, os, re, sys
found = set()
for path in glob.glob(os.path.join(sys.argv[1], "Payload*.swift")):
    for line in open(path, encoding="utf-8"):
        m = re.match(r"\s*(?:public|package|open)\b\s*(\w+(?: \w+)?)", line)
        if m:
            found.add((os.path.basename(path), m.group(0).strip().split("(")[0]))
assert found == {("PayloadSession.swift", "package actor PayloadSession"), ("PayloadSession.swift", "package init"),
                 ("PayloadProblem.swift", "package init")}, sorted(found)
print("ok")
PY
}

@test "the JavaScript checks use block comments only" {
  run grep -nE '^[[:space:]]*//' "$TPL/scripts/check/i18n-catalog.mjs"
  [ "$status" -eq 1 ]
}

@test "SwiftLint is pinned in .swiftlint.yml to the version the quality gate installs" {
  run sed -n 's/^swiftlint_version: \([0-9.]*\).*/\1/p' "$TPL/.swiftlint.yml"
  [ "$output" = "0.65.1" ]
  local lock="$KIT_ROOT/actions/quality-gate/scripts/tools.lock"
  [ -f "$lock" ] || skip "the quality gate's tools.lock is not in this tree"
  run awk '$1 == "swiftlint" { print $2 }' "$lock"
  [ -n "$output" ]
  [ "$(sort -u <<<"$output")" = "0.65.1" ]
}

@test "the strict SwiftLint settings the rules count on" {
  run -0 python3 - "$TPL/.swiftlint.yml" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
for needle in ("strict: true", "ignore_comment_only_lines: true", "superfluous_disable_command: error",
               "allowed_rules: []", "excluded_types: []", "excludes_inherited_types: false",
               "default_execution_mode: swiftsyntax"):
    assert needle in text, needle
assert re.search(r"file_length:\n  warning: 150\n  error: 150", text)
for rule in ("no_ui_import_in_logic", "no_text_verbatim", "package_text_names_bundle", "no_unlocalized_format",
             "no_route_literal", "no_urlsession_outside_transport", "no_default_on_problem_code", "no_status_branch",
             "no_token_in_user_defaults", "no_any_type", "no_print", "empty_catch_reason"):
    assert f"\n  {rule}:\n" in text, rule
print("ok")
PY
}

@test "AGENTS.md indexes Rules 1 to 33 once each, every row with its enforcer and a detail that exists" {
  run -0 python3 - "$TPL" "$CORE_TPL" <<'PY'
import os, re, sys
tpl, core = sys.argv[1], sys.argv[2]
rows = [l for l in open(os.path.join(tpl, "AGENTS.md.starter")) if re.match(r"^\| \d+ \|", l)]
numbers = [int(r.split("|")[1]) for r in rows]
assert numbers == list(range(1, 34)), numbers
missing = []
for r in rows:
    cells = [c.strip() for c in r.strip().strip("|").split("|")]
    assert len(cells) == 4 and all(cells), cells
    detail = cells[3].strip("`")
    if not (os.path.exists(os.path.join(tpl, detail)) or os.path.exists(os.path.join(core, detail))):
        missing.append(detail)
# The swift type and dead-code rules ship with agent-core's language question.
missing = [m for m in missing if not (m.startswith(".claude/rules/swift/") and not os.path.isdir(os.path.join(core, ".claude/rules/swift")))]
assert not missing, missing
print("ok")
PY
}

@test "CLAUDE.md stays a short pointer table; every rule file loads by paths" {
  [ "$(wc -c <"$TPL/CLAUDE.md.starter")" -lt 1024 ]
  local f
  while IFS= read -r f; do
    [ "$(head -1 "$f")" = "---" ]
    sed -n '2,/^---$/p' "$f" | grep -q '^paths:'
  done < <(find "$TPL/.claude/rules" -name '*.md')
}

@test "the anti-pattern index lists every file, and every file is listed" {
  local f name
  [ "$(find "$TPL/.claude/anti-patterns" -name '*.md' ! -name INDEX.md | wc -l | tr -d ' ')" -eq 12 ]
  for f in "$TPL"/.claude/anti-patterns/*.md; do
    name="$(basename "$f")"
    [ "$name" = INDEX.md ] && continue
    grep -qF "| $name |" "$TPL/.claude/anti-patterns/INDEX.md" || {
      echo "INDEX.md does not list $name" >&2
      return 1
    }
  done
}

@test "every JSON file is strict JSON, and settings allow only named commands" {
  local f
  while IFS= read -r f; do
    jq empty "$f"
  done < <(find "$TPL" -name '*.json')
  run jq -r '.permissions.allow[]' "$TPL/.claude/settings.json"
  run ! grep -qE '^Bash\((xcodebuild|xcrun|swift (run|package)|bash|sh|node|python3?)(:\*)?\)$' <<<"$output"
  run jq -r 'has("hooks")' "$TPL/.claude/settings.json"
  [ "$output" = "false" ]
}

@test "the seeded Swift files hold at most 150 code lines each" {
  local f n
  while IFS= read -r f; do
    n="$(grep -cvE '^[[:space:]]*($|//)' "$f")"
    [ "$n" -le 150 ] || {
      echo "$f has $n code lines" >&2
      return 1
    }
  done < <(find "$TPL" -name '*.swift' -o -name '*.swift.starter')
}

@test "the CI caller calls the ios-swiftui gate pinned to a commit, with a release comment" {
  run grep -E '^\s*uses: ' "$TPL/.github/workflows/quality-gate.yml"
  [[ "$output" =~ uses:\ adhibuchori/agent-config-kit/\.github/workflows/ios-swiftui-quality-gate\.yml@[0-9a-f]{40}\ \#\ v[0-9]+\.[0-9]+\.[0-9]+$ ]] || false
  run grep -E '^\s*(push|schedule|pull_request_target):' "$TPL/.github/workflows/quality-gate.yml"
  [ "$status" -eq 1 ]
}

@test "the generator config sits where the gate's drift check looks, and decodes problems leniently" {
  local cfg="$TPL/Packages/AppCore/Sources/APIClient/openapi-generator-config.yaml"
  [ -f "$cfg" ]
  grep -qx '    Problem: AppProblem' "$cfg"
  grep -qx 'accessModifier: internal' "$cfg"
  [ -f "$TPL/.periphery.yml" ]
}
