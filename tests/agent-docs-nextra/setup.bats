#!/usr/bin/env bats
# /agent-docs-nextra:setup and :sync end to end, through agent-core's engine with this plugin's
# templates: draft, digest, no-clobber, the managed merges, drift and double wiring.

load helpers

setup() {
  dn_engine || skip "agent-core's bin/agent-setup and bin/agent-sync are not built yet"
  SITE="$(dn_site)"
  ARGS=(--templates "$DN_TEMPLATES" --stack docs-nextra --project "$SITE")
}

# plan with the given answers, then apply exactly that draft.
dn_setup_all() {
  run -0 --separate-stderr "$DN_CORE/bin/agent-setup" plan "${ARGS[@]}" "$@"
  DIGEST="$(printf '%s\n' "$output" | sed -n 's/^digest \(sha256:[0-9a-f]\{64\}\)$/\1/p')"
  [ -n "$DIGEST" ]
  run -0 --separate-stderr "$DN_CORE/bin/agent-setup" apply "${ARGS[@]}" "$@" --digest "$DIGEST"
}

@test "questions: agent-core's layer first, then this plugin's four, each with a recommended answer" {
  run -0 --separate-stderr "$DN_CORE/bin/agent-setup" questions "${ARGS[@]}" --json
  run -0 python3 -c '
import json, sys
d = json.loads(sys.argv[1])
ids = [q["id"] for q in d["questions"]]
assert d["plugin"] == "agent-docs-nextra" and d["stack"] == "docs-nextra", d
assert ids[-4:] == ["generated-pages", "ci-pipeline", "react-doctor", "analytics"], ids
assert all(q["recommended"] in q["choices"] for q in d["questions"])
print("ok")' "$output"
  [ "$output" = ok ]
}

@test "an unknown answer is a usage error, and apply needs the draft's digest" {
  run -2 --separate-stderr "$DN_CORE/bin/agent-setup" plan "${ARGS[@]}" --answer ci-pipeline=maybe
  run -3 --separate-stderr "$DN_CORE/bin/agent-setup" apply "${ARGS[@]}" --digest "sha256:$(printf '0%.0s' {1..64})"
  [ ! -e "$SITE/.claude/agent-config-kit.lock" ]
  [ ! -e "$SITE/.claude/anti-patterns/INDEX.md" ]
}

@test "setup keeps the user's CLAUDE.md and files, adds one block, and writes the lock last" {
  printf '# Toy docs\n\nOur own notes, written before setup.\n' >"$SITE/CLAUDE.md"
  printf '// our own lint config\n{}\n' >"$SITE/oxlint.json"
  local before_claude before_oxlint
  before_claude="$(cat "$SITE/CLAUDE.md")"
  before_oxlint="$(cat "$SITE/oxlint.json")"
  dn_setup_all --answer generated-pages=yes
  [[ "$(cat "$SITE/CLAUDE.md")" == "$before_claude"* ]] || false
  [ "$(grep -c '^<!-- >>> agent-config-kit' "$SITE/CLAUDE.md")" -eq 1 ]
  grep -q '^### Docs site (agent-docs-nextra)$' "$SITE/CLAUDE.md"
  [ "$(cat "$SITE/oxlint.json")" = "$before_oxlint" ]
  [ -f "$SITE/.claude/agent-config-kit.lock" ]
  cmp "$SITE/.claude/agent-config.json" "$DN_STACK/.claude/agent-config.json"
  cmp "$SITE/scripts/check/gates.list" "$DN_STACK/scripts/check/gates.list"
  [ -x "$SITE/.github/scripts/check-comment-blocks.sh" ]
}

@test "a repo without CLAUDE.md gets the starter plus the block, within the always-loaded budget" {
  dn_setup_all
  # shellcheck disable=SC2016 # backticks are Markdown here, not a command
  grep -q '^# CLAUDE.md — `<Project Name>` Docs$' "$SITE/CLAUDE.md"
  [ "$(grep -c '^<!-- >>> agent-config-kit' "$SITE/CLAUDE.md")" -eq 1 ]
  dn_git -C "$SITE" add -A
  # shellcheck disable=SC2016 # $1 expands in the child shell
  run -0 bash -c 'cd "$1" && bash scripts/check/ai-config.sh' _ "$SITE"
  [[ "$output" == *"AI config within budget"* ]] || false
}

@test "the managed merges: settings without hooks, package scripts added, nothing overwritten" {
  dn_setup_all
  run -0 python3 - "$SITE" <<'PY'
import json, sys
site = sys.argv[1]
s = json.load(open(site + "/.claude/settings.json"))
assert "hooks" not in s, s.keys()
for rule in ("Bash(bun run fl:*)", "Bash(bun fl:*)", "Bash(bun check:*)"):
    assert rule in s["permissions"]["allow"], rule
assert "Bash(bun run:*)" not in s["permissions"]["allow"], s["permissions"]["allow"]
p = json.load(open(site + "/package.json"))
assert p["scripts"]["dev"] == "next dev" and p["scripts"]["build"] == "next build", p["scripts"]
for name in ("env:init", "format", "fl", "fl:ci", "type-check", "check:dead-code", "unlock"):
    assert name in p["scripts"], name
# Every package script the installed files tell the user to run exists.
assert p["scripts"]["env:init"] == "bun run scripts/next/env.ts init", p["scripts"]["env:init"]
print("ok")
PY
  grep -qx '.env.development' "$SITE/.gitignore"
  grep -qx '.generation-marker' "$SITE/.gitignore"
  [ "$(head -n 1 "$SITE/.gitignore")" = "node_modules/" ]
}

@test "a package script the user already defines differently is kept" {
  python3 - "$SITE/package.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
p["scripts"]["type-check"] = "tsc -p tsconfig.app.json --noEmit"
open(sys.argv[1], "w").write(json.dumps(p, indent=2) + "\n")
PY
  dn_setup_all
  grep -q '"type-check": "tsc -p tsconfig.app.json --noEmit"' "$SITE/package.json"
}

@test "no package.json: no scripts, no alias, and none is created" {
  rm "$SITE/package.json"
  dn_setup_all
  [ ! -e "$SITE/package.json" ]
}

@test "the answers gate the optional files" {
  dn_setup_all --answer ci-pipeline=no --answer react-doctor=no --answer analytics=no --answer generated-pages=no
  # The CI caller is installed once a release pins a real commit; until then setup holds it back.
  if grep -Eq '@0{40}' "$DN_STACK/.github/workflows/quality-gate.yaml"; then
    [ ! -e "$SITE/.github/workflows/quality-gate.yaml" ]
  else
    [ -f "$SITE/.github/workflows/quality-gate.yaml" ]
  fi
  [ ! -e "$SITE/.github/workflows/changelog.yaml" ]
  [ ! -e "$SITE/.github/workflows/ci-cd.yaml" ]
  [ ! -e "$SITE/wrangler.example.jsonc" ]
  [ ! -e "$SITE/.github/workflows/react-doctor.yml" ]
  [ ! -e "$SITE/doctor.config.json" ]
  [ ! -e "$SITE/.claude/ANALYTICS.example.md" ]
  [ ! -e "$SITE/.claude/agent-config.json" ]
}

@test "the yes answers install the pipeline, React Doctor and the analytics template" {
  dn_setup_all --answer ci-pipeline=yes --answer react-doctor=yes --answer analytics=yes --answer generated-pages=yes
  [ -f "$SITE/.github/workflows/changelog.yaml" ]
  [ -f "$SITE/.github/workflows/ci-cd.yaml" ]
  [ -f "$SITE/wrangler.example.jsonc" ]
  [ -f "$SITE/.github/workflows/react-doctor.yml" ]
  [ -f "$SITE/.claude/ANALYTICS.example.md" ]
}

@test "sync --check: 0 right after setup, 1 on drift, 4 on double wiring, 5 on both, byte-stable" {
  dn_setup_all
  run -0 --separate-stderr "$DN_CORE/bin/agent-sync" check "${ARGS[@]}"
  local first="$output"
  run -0 --separate-stderr "$DN_CORE/bin/agent-sync" check "${ARGS[@]}"
  [ "$output" = "$first" ]

  printf '\nlocal note\n' >>"$SITE/.claude/anti-patterns/nextra-zod-v4-bug.md"
  run -1 --separate-stderr "$DN_CORE/bin/agent-sync" check "${ARGS[@]}"
  [[ "$output" == *"modified  .claude/anti-patterns/nextra-zod-v4-bug.md"* ]] || false

  python3 - "$SITE/.claude/settings.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
s["hooks"] = {"PreToolUse": [{"matcher": "Write|Edit", "hooks": [{"type": "command",
    "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/generated-guard.sh\"", "timeout": 10}]}]}
open(sys.argv[1], "w").write(json.dumps(s, indent=2) + "\n")
PY
  run -5 --separate-stderr "$DN_CORE/bin/agent-sync" check "${ARGS[@]}"
  [[ "$output" == *"double-wired  .claude/settings.json  hooks.PreToolUse[0] runs generated-guard.sh, which agent-docs-nextra also runs"* ]] || false

  cp "$DN_STACK/.claude/anti-patterns/nextra-zod-v4-bug.md" "$SITE/.claude/anti-patterns/nextra-zod-v4-bug.md"
  run -4 --separate-stderr "$DN_CORE/bin/agent-sync" check "${ARGS[@]}"
}

@test "sync restores a deleted managed file and a lost exec bit after a draft" {
  dn_setup_all
  rm "$SITE/scripts/next/run.mjs"
  chmod 644 "$SITE/.github/scripts/check-comment-blocks.sh"
  run -1 --separate-stderr "$DN_CORE/bin/agent-sync" check "${ARGS[@]}"
  run -0 --separate-stderr "$DN_CORE/bin/agent-sync" plan "${ARGS[@]}"
  local digest
  digest="$(printf '%s\n' "$output" | sed -n 's/^digest \(sha256:[0-9a-f]\{64\}\)$/\1/p')"
  run -0 --separate-stderr "$DN_CORE/bin/agent-sync" apply "${ARGS[@]}" --digest "$digest"
  cmp "$SITE/scripts/next/run.mjs" "$DN_STACK/scripts/next/run.mjs"
  [ -x "$SITE/.github/scripts/check-comment-blocks.sh" ]
  run -0 --separate-stderr "$DN_CORE/bin/agent-sync" check "${ARGS[@]}"
}

@test "a repo already set up for another primary stack is refused" {
  mkdir -p "$SITE/.claude"
  printf '{"kit": "agent-config-kit", "lockVersion": 1, "blocks": {}, "plugins": {"agent-fe-nextjs": {"stack": "fe-nextjs", "version": "1.0.0", "files": {}}}}\n' \
    >"$SITE/.claude/agent-config-kit.lock"
  run -3 --separate-stderr "$DN_CORE/bin/agent-setup" plan "${ARGS[@]}"
  [[ "$stderr$output" == *agent-fe-nextjs* ]] || false
}

@test "after setup, the plugin's hook guards the generated pages the answers named" {
  dn_setup_all --answer generated-pages=yes
  run -2 --separate-stderr dn_guard "$SITE" "$(dn_payload Edit "{\"file_path\": \"$SITE/content/technical/api.mdx\"}")"
  [[ "$stderr" == *"content/technical/api.mdx is generated output"* ]] || false
  run -0 --separate-stderr dn_guard "$SITE" "$(dn_payload Edit "{\"file_path\": \"$SITE/content/index.mdx\"}")"
}
