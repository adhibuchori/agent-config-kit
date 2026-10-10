#!/usr/bin/env bats
# /agent-be-go:setup and :sync end to end, through agent-core's engine with this plugin's
# templates: the questions, the draft and its digest, go.mod kept with a by-hand line or created
# from the starter, the seeded skeleton, the held CI caller, drift, and a conflicting stack.

load helpers

setup() {
  go_setup_env
  go_engine || skip "agent-core's bin/agent-setup and bin/agent-sync are not built yet"
  make_project
  go_args
}

@test "questions: agent-core's layer first, then this plugin's six, each recommending one of its choices" {
  run -0 --separate-stderr "$SETUP_BIN" questions "${ARGS[@]}" --json
  run -0 python3 -c '
import json, sys
d = json.loads(sys.argv[1])
assert d["plugin"] == "agent-be-go" and d["stack"] == "be-go", d
ids = [(q["plugin"], q["id"]) for q in d["questions"]]
assert ids[0] == ("agent-core", "language"), ids
assert [i for p, i in ids if p == "agent-be-go"] == ["migrations", "ci-gate", "deepseek-review", "pr-templates",
                                                     "analytics", "serena-workspace"], ids
assert all(q["recommended"] in q["choices"] and q["why"] for q in d["questions"])
print("ok")' "$output"
  [ "$output" = ok ]
}

@test "an unknown answer is a usage error, and apply writes nothing without the draft's digest" {
  run -2 --separate-stderr "$SETUP_BIN" plan "${ARGS[@]}" --answer migrations=maybe
  run -3 --separate-stderr "$SETUP_BIN" apply "${ARGS[@]}" --digest "sha256:$(printf '0%.0s' {1..64})"
  [[ "$stderr" == *"the project changed since the draft"* ]] || false
  [ ! -e "$PROJ/.claude/agent-config-kit.lock" ]
  run git -C "$PROJ" status --porcelain --untracked-files=all
  [ -z "$output" ]
}

@test "the draft: go.mod kept with a by-hand line, the skeleton seeded, the CI caller held back" {
  run -0 --separate-stderr "$SETUP_BIN" plan "${ARGS[@]}"
  [[ "$output" == *"agent-setup plan · agent-be-go $PLUGIN_VERSION + agent-core $CORE_VERSION · project "* ]] || false
  grep -qE '^  keep +go\.mod +\(exists; left alone; compare with agent-be-go templates/be-go/go\.mod\.starter\)$' <<<"$output"
  grep -qE '^  by-hand +go\.mod +add what .*/templates/be-go/_kit/snippets/go\.mod\.tools holds' <<<"$output"
  grep -qE '^  seed +go\.sum ' <<<"$output"
  grep -qE '^  seed +internal/apperr/codes\.go ' <<<"$output"
  grep -qE '^  seed +internal/httpapi/api\.gen\.go ' <<<"$output"
  grep -qE '^  seed +db/roles\.sql ' <<<"$output"
  grep -qE '^  seed +\.claude/agent-config\.json ' <<<"$output"
  grep -qE '^  create +\.claude/rules/backend/postgres\.md$' <<<"$output"
  grep -qE '^  create +scripts/check/generated\.sh$' <<<"$output"
  grep -qE '^  block +CLAUDE\.md +## Agent config kit \(new file\) from the starter$' <<<"$output"
  if grep -Eq '@0{40}' "$TPL/.github/workflows/quality-gate.yml"; then
    grep -qE '^  warn +\.github/workflows/quality-gate\.yml +not installed: .*release placeholder' <<<"$output"
  else
    grep -qE '^  create +\.github/workflows/quality-gate\.yml' <<<"$output"
  fi
  grep -qE '^  note +package\.json +none here, so no unlock script is added' <<<"$output"
  [[ "${lines[${#lines[@]} - 1]}" =~ ^digest\ sha256:[0-9a-f]{64}$ ]] || false
}

@test "setup writes the draft and nothing else: go.mod and the service's own code untouched, lock last" {
  local before
  before="$(shasum -a 256 "$PROJ/go.mod" "$PROJ/cmd/inventory/main.go" "$PROJ/db/migrations/00001_create_things.sql")"
  go_setup
  [ "$(shasum -a 256 "$PROJ/go.mod" "$PROJ/cmd/inventory/main.go" "$PROJ/db/migrations/00001_create_things.sql")" = "$before" ]
  [ ! -e "$PROJ/package.json" ]
  [ -f "$PROJ/.claude/agent-config-kit.lock" ]
  cmp "$PROJ/AGENTS.md" "$TPL/AGENTS.md.starter"
  cmp "$PROJ/go.sum" "$TPL/go.sum.starter"
  cmp "$PROJ/internal/apperr/codes.go" "$TPL/internal/apperr/codes.go"
  cmp "$PROJ/.claude/rules/backend/postgres.md" "$TPL/.claude/rules/backend/postgres.md"
  [ -x "$PROJ/.githooks/pre-commit" ]
  [ -x "$PROJ/scripts/check/coverage.sh" ]
  [ -f "$PROJ/.squawk.toml" ]
  [ -f "$PROJ/.github/PULL_REQUEST_TEMPLATE/dev.md" ]
  [ ! -e "$PROJ/.claude/ANALYTICS.example.md" ]
  [ ! -e "$PROJ/.github/workflows/deepseek-review.yml" ]
  if grep -Eq '@0{40}' "$TPL/.github/workflows/quality-gate.yml"; then
    [ ! -e "$PROJ/.github/workflows/quality-gate.yml" ]
  fi
  [ "$(head -n 1 "$PROJ/CLAUDE.md")" = "$(head -n 1 "$TPL/CLAUDE.md.starter")" ]
  grep -qx '### Go service (agent-be-go)' "$PROJ/CLAUDE.md"
  grep -qx '/coverage/' "$PROJ/.gitignore"
  grep -qx '!.env.ci.example' "$PROJ/.gitignore"
  run -0 python3 - "$PROJ" <<'PY'
import json, sys
root = sys.argv[1]
s = json.load(open(root + "/.claude/settings.json"))
assert "hooks" not in s, sorted(s)
allow, ask = s["permissions"]["allow"], s["permissions"]["ask"]
for rule in ("Bash(bash scripts/check/gates.sh:*)", "Bash(go test:*)", "Bash(golangci-lint run:*)"):
    assert rule in allow, rule
for rule in ("Bash(go run:*)", "Bash(go generate:*)", "Bash(go tool goose:*)"):
    assert rule in ask and rule not in allow, rule
assert "Edit(AGENTS.md)" in s["permissions"]["deny"]
cfg = json.load(open(root + "/.claude/agent-config.json"))
assert cfg["appendOnlyMigrationsDirs"] == ["db/migrations"], cfg
assert "internal/httpapi/api.gen.go" in cfg["generatedPaths"], cfg
lock = json.load(open(root + "/.claude/agent-config-kit.lock"))
me = lock["plugins"]["agent-be-go"]
assert me["stack"] == "be-go", me
assert me["kept"] == ["go.mod"], me["kept"]
assert me["answers"] == {"migrations": "yes", "ci-gate": "yes", "deepseek-review": "no", "pr-templates": "yes",
                         "analytics": "no", "serena-workspace": "no"}, me["answers"]
assert "internal/httpapi/router.go" in me["seeded"] and "AGENTS.md" in me["seeded"], me["seeded"]
print("ok")
PY
}

@test "a repo without go.mod gets the starter, and sync --check is in sync right after setup" {
  git -C "$PROJ" rm -q go.mod
  git -C "$PROJ" commit -q -m "no go.mod"
  go_setup
  cmp "$PROJ/go.mod" "$TPL/go.mod.starter"
  grep -qE '^  seed +go\.mod ' <<<"$PLAN"
  run --separate-stderr "$SYNC_BIN" check "${ARGS[@]}"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "${lines[${#lines[@]} - 1]}" == "result: in sync (0 findings; exit 0)" ]] || false
}

@test "the installed repo passes agent-core's ai-config check: citations resolve, context in budget" {
  go_setup
  git -C "$PROJ" add -A
  # shellcheck disable=SC2016 # $1 expands in the child shell
  run -0 --separate-stderr bash -c 'cd "$1" && bash scripts/check/ai-config.sh' _ "$PROJ"
  [[ "$output" == *"All cited rule numbers are defined in AGENTS.md"* ]] || false
  [[ "$output" == *"AI config within budget"* ]] || false
}

@test "the optional answers gate their files" {
  go_setup --answer migrations=no --answer ci-gate=no --answer pr-templates=no \
    --answer deepseek-review=yes --answer analytics=yes --answer serena-workspace=yes
  [ ! -e "$PROJ/.squawk.toml" ]
  [ ! -e "$PROJ/.github/workflows/quality-gate.yml" ]
  [ ! -e "$PROJ/.github/PULL_REQUEST_TEMPLATE" ]
  cmp "$PROJ/.github/workflows/deepseek-review.yml" "$TPL/.github/workflows/deepseek-review.yml"
  cmp "$PROJ/.claude/ANALYTICS.example.md" "$TPL/.claude/ANALYTICS.example.md"
  cmp "$PROJ/.claude/SERENA-WORKSPACE.example.md" "$TPL/.claude/SERENA-WORKSPACE.example.md"
  # The roles and the guard's settings stay: the tests need the roles whoever owns the schema.
  [ -f "$PROJ/db/roles.sql" ]
  [ -f "$PROJ/.claude/agent-config.json" ]
}

@test "a second setup plans nothing, and sync on an unchanged repo writes nothing" {
  go_setup
  local lock
  lock="$(shasum -a 256 "$PROJ/.claude/agent-config-kit.lock")"
  run -0 --separate-stderr "$SETUP_BIN" plan "${ARGS[@]}"
  [ "$output" = "already set up (agent-be-go $PLUGIN_VERSION); run /agent-be-go:sync" ]
  run -0 --separate-stderr "$SYNC_BIN" plan "${ARGS[@]}"
  [[ "$output" == *"(nothing to write)"* ]] || false
  [ "$(shasum -a 256 "$PROJ/.claude/agent-config-kit.lock")" = "$lock" ]
}

@test "a kit-managed script edited by hand is drift; a seeded file edited by hand is not" {
  go_setup
  printf '\n# local change\n' >>"$PROJ/scripts/check/endpoints.sh"
  printf '\n// our own change\n' >>"$PROJ/internal/apperr/codes.go"
  run --separate-stderr "$SYNC_BIN" check "${ARGS[@]}"
  [ $((status & 1)) -eq 1 ]
  [[ "$output" == *"modified  scripts/check/endpoints.sh"* ]] || false
  [[ "$output" != *"modified  internal/apperr/codes.go"* ]] || false
}

@test "a repo already set up with another primary stack is refused" {
  local other
  for other in $CONFLICTS; do
    mkdir -p "$PROJ/.claude"
    printf '{"plugins": {"%s": {"stack": "x", "version": "1.0.0"}}}\n' "$other" >"$PROJ/.claude/agent-config-kit.lock"
    run -3 --separate-stderr "$SETUP_BIN" plan "${ARGS[@]}"
    [[ "$stderr" == *"agent-be-go conflicts with $other"* ]] || false
  done
}
