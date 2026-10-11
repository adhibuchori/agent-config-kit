#!/usr/bin/env bats
# /agent-ios-swiftui:setup and :sync end to end, through agent-core's engine with this plugin's
# templates: the questions, the draft, what is written and what is held, the locales answer, no
# package.json, the AI-config check on the installed repo, sync, and a conflicting stack.

load helpers

setup() {
  ios_setup_env
  ios_engine || skip "agent-core's bin/agent-setup and bin/agent-sync are not built yet"
  PROJ="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$PROJ"
  cp -R "$FIXTURES/app/Orders.xcodeproj" "$PROJ/"
  git -C "$PROJ" init -q
  git -C "$PROJ" add -A
  git -C "$PROJ" commit -q -m "the Xcode project"
  PROJ="$(cd "$PROJ" && pwd -P)"
}

@test "questions: agent-core's layer first, then this plugin's eight, each recommending one of its choices" {
  run -0 --separate-stderr "$SETUP_BIN" questions --templates "$PLUGIN/templates" --stack ios-swiftui --project "$PROJ" --json
  run -0 python3 -c '
import json, sys
d = json.loads(sys.argv[1])
assert d["plugin"] == "agent-ios-swiftui" and d["stack"] == "ios-swiftui", d
ids = [(q["plugin"], q["id"]) for q in d["questions"]]
assert ids[0] == ("agent-core", "language"), ids
mine = [i for p, i in ids if p == "agent-ios-swiftui"]
assert mine == ["ci-gate", "deepseek-review", "pr-templates", "serena-workspace", "min-ios", "locales", "analytics",
                "payload-encryption"], mine
assert all(q["recommended"] in q["choices"] and q["why"] for q in d["questions"])
print("ok")' "$output"
  [ "$output" = ok ]
}

@test "the draft: starters seeded, the CI caller held while it pins the placeholder, no package.json" {
  run -0 --separate-stderr "$SETUP_BIN" plan --templates "$PLUGIN/templates" --stack ios-swiftui --project "$PROJ"
  [[ "${lines[${#lines[@]} - 1]}" =~ ^digest\ sha256:[0-9a-f]{64}$ ]] || false
  grep -qE '^  seed +AGENTS\.md ' <<<"$output"
  grep -qE '^  seed +Packages/AppCore/Package\.swift ' <<<"$output"
  grep -qE '^  seed +Packages/AppCore/Sources/APIClient/AppProblem\.swift ' <<<"$output"
  grep -qE '^  seed +\.periphery\.yml ' <<<"$output"
  grep -qE '^  create +scripts/check/coverage\.sh' <<<"$output"
  grep -qE '^  block +CLAUDE\.md +## Agent config kit \(new file\) from the starter$' <<<"$output"
  grep -qE '^  note +package\.json +none here' <<<"$output"
  if grep -Eq '@0{40}' "$TPL/.github/workflows/quality-gate.yml"; then
    grep -qE '^  warn +\.github/workflows/quality-gate\.yml +not installed: .*release placeholder' <<<"$output"
  else
    grep -qE '^  create +\.github/workflows/quality-gate\.yml' <<<"$output"
  fi
  # locales=en (recommended) installs no locale list; the check then reads each catalog's own.
  run ! grep -q 'scripts/check/i18n-catalog.json' <<<"$output"
}

@test "setup writes the draft: the project file untouched, scripts executable, lock last, answers recorded" {
  local before
  before="$(shasum -a 256 "$PROJ/Orders.xcodeproj/project.pbxproj")"
  ios_setup --answer locales=en,id --answer min-ios=18.0
  [ "$(shasum -a 256 "$PROJ/Orders.xcodeproj/project.pbxproj")" = "$before" ]
  [ ! -e "$PROJ/package.json" ]
  cmp "$PROJ/AGENTS.md" "$TPL/AGENTS.md.starter"
  cmp "$PROJ/Packages/AppCore/Package.swift" "$TPL/Packages/AppCore/Package.swift.starter"
  cmp "$PROJ/scripts/check/i18n-catalog.json" "$TPL/scripts/check/i18n-catalog.json"
  local f
  for f in coverage error-codes lint-suppressions package-graph privacy-manifest xcode-settings ci-env; do
    [ -x "$PROJ/scripts/check/$f.sh" ]
  done
  [ -x "$PROJ/scripts/ios/app.sh" ] && [ -x "$PROJ/scripts/ios/api-client.sh" ] && [ -x "$PROJ/.githooks/pre-commit" ]
  grep -qx '/coverage' "$PROJ/.gitignore"
  grep -qx '.build/' "$PROJ/.gitignore"
  run -0 python3 - "$PROJ" <<'PY'
import json, sys
root = sys.argv[1]
s = json.load(open(root + "/.claude/settings.json"))
assert "hooks" not in s, sorted(s)
allow, ask = s["permissions"]["allow"], s["permissions"]["ask"]
for rule in ("Bash(bash scripts/check/gates.sh:*)", "Bash(bash scripts/ios/app.sh:*)", "Bash(swift test:*)"):
    assert rule in allow, rule
for rule in ("Bash(xcodebuild:*)", "Bash(swift package:*)", "Bash(swift run:*)"):
    assert rule in ask and rule not in allow, rule
lock = json.load(open(root + "/.claude/agent-config-kit.lock"))
me = lock["plugins"]["agent-ios-swiftui"]
assert me["stack"] == "ios-swiftui", me
assert me["answers"] == {"ci-gate": "yes", "deepseek-review": "no", "pr-templates": "yes", "serena-workspace": "no",
                         "min-ios": "18.0", "locales": "en,id", "analytics": "no",
                         "payload-encryption": "no"}, me["answers"]
assert "AGENTS.md" in me["seeded"] and "CLAUDE.md" in me["seeded"], me["seeded"]
print("ok")
PY
}

@test "right after setup, sync --check is in sync" {
  ios_setup
  run --separate-stderr "$SYNC_BIN" check --templates "$PLUGIN/templates" --stack ios-swiftui --project "$PROJ"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "${lines[${#lines[@]} - 1]}" == "result: in sync (0 findings; exit 0)" ]] || false
}

@test "the installed repo passes agent-core's ai-config check: citations resolve, context in budget" {
  ios_setup
  git -C "$PROJ" add -A
  # shellcheck disable=SC2016 # $1 expands in the child shell
  run -0 --separate-stderr bash -c 'cd "$1" && bash scripts/check/ai-config.sh' _ "$PROJ"
  [[ "$output" == *"All cited rule numbers are defined in AGENTS.md"* ]] || false
  [[ "$output" == *"AI config within budget"* ]] || false
}

@test "the optional answers gate their files" {
  ios_setup --answer ci-gate=no --answer pr-templates=no --answer analytics=yes --answer serena-workspace=yes
  [ ! -e "$PROJ/.github/workflows/quality-gate.yml" ]
  [ ! -e "$PROJ/.github/PULL_REQUEST_TEMPLATE" ]
  cmp "$PROJ/.claude/ANALYTICS.example.md" "$TPL/.claude/ANALYTICS.example.md"
  cmp "$PROJ/.claude/SERENA-WORKSPACE.example.md" "$TPL/.claude/SERENA-WORKSPACE.example.md"
}

@test "payload-encryption=yes installs the app's half of the payload contract; no installs none of it" {
  local f
  ios_setup
  [ -f "$PROJ/scripts/check/payload-registry.mjs" ] && [ -f "$PROJ/scripts/lib/payload-registry.mjs" ]
  [ ! -e "$PROJ/payload.config.json" ] && [ ! -e "$PROJ/.claude/PAYLOAD-CONTRACT.md" ]
  [ ! -e "$PROJ/scripts/check/payload-vectors.json" ] && [ ! -e "$PROJ/.claude/rules/ios/payload.md" ]
  run -0 find "$PROJ/Packages" -name 'Payload*'
  [ -z "$output" ]
  # shellcheck disable=SC2016 # $1 expands in the child shell
  run -0 --separate-stderr bash -c 'cd "$1" && node scripts/check/payload-registry.mjs' _ "$PROJ"
  [[ "$output" == *"not adopted"* ]] || false

  rm -rf "$PROJ"
  mkdir -p "$PROJ"
  git -C "$PROJ" init -q
  ios_setup --answer payload-encryption=yes
  for f in .claude/PAYLOAD-CONTRACT.md .claude/rules/common/payload-contract.md .claude/rules/ios/payload.md \
    payload.config.json scripts/check/payload-vectors.json; do
    cmp "$PROJ/$f" "$TPL/$f"
  done
  for f in "$TPL"/Packages/AppCore/Sources/APIClient/Payload*.swift "$TPL"/Packages/AppCore/Tests/APIClientTests/Payload*.swift; do
    cmp "$PROJ/${f#"$TPL/"}" "$f"
  done
  run -0 python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["plugins"]["agent-ios-swiftui"]["answers"]["payload-encryption"])' \
    "$PROJ/.claude/agent-config-kit.lock"
  [ "$output" = yes ]
}

@test "a repo already set up with another primary stack is refused" {
  mkdir -p "$PROJ/.claude"
  printf '{"plugins": {"agent-be-hono": {"stack": "be-hono", "version": "1.0.0"}}}\n' \
    >"$PROJ/.claude/agent-config-kit.lock"
  run -3 --separate-stderr "$SETUP_BIN" plan --templates "$PLUGIN/templates" --stack ios-swiftui --project "$PROJ"
  [[ "$stderr" == *"agent-ios-swiftui conflicts with agent-be-hono"* ]] || false
}
