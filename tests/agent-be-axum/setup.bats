#!/usr/bin/env bats
# /agent-be-axum:setup and :sync end to end, through agent-core's engine with this plugin's
# templates: the questions, the draft, a new repo and an existing crate, the migrations answer, the
# held CI caller, sync, the AI-config check, and a conflicting stack.

load helpers

setup() {
  ax_setup_env
  ax_engine || skip "agent-core's bin/agent-setup and bin/agent-sync are not built yet"
  make_project empty
  ax_args
}

@test "questions: agent-core's layer first, then this plugin's six, each recommending one of its choices" {
  run -0 --separate-stderr "$SETUP_BIN" questions "${ARGS[@]}" --json
  run -0 python3 -c '
import json, sys
d = json.loads(sys.argv[1])
assert d["plugin"] == "agent-be-axum" and d["stack"] == "be-axum", d
ids = [(q["plugin"], q["id"]) for q in d["questions"]]
assert ids[0] == ("agent-core", "language"), ids
assert [i for p, i in ids if p == "agent-be-axum"] == ["migrations", "ci-gate", "deepseek-review", "pr-templates",
                                                      "analytics", "serena-workspace"], ids
assert all(q["recommended"] in q["choices"] and q["why"] for q in d["questions"])
print("ok")' "$output"
  [ "$output" = ok ]
}

@test "a new repo: Cargo.toml and CLAUDE.md from the starters, the skeleton seeded, the caller held" {
  ax_setup
  grep -qE '^  seed +Cargo\.toml ' <<<"$PLAN"
  grep -qE '^  by-hand +Cargo\.toml +add what .*/templates/be-axum/_kit/snippets/cargo\.toml holds' <<<"$PLAN"
  grep -qE '^  note +package\.json +none here' <<<"$PLAN"
  grep -qE '^  block +CLAUDE\.md +## Agent config kit \(new file\) from the starter$' <<<"$PLAN"
  grep -qE '^  warn +\.github/workflows/quality-gate\.yml +not installed: .*release placeholder' <<<"$PLAN"
  cmp "$PROJ/Cargo.toml" "$TPL/Cargo.toml.starter"
  cmp "$PROJ/AGENTS.md" "$TPL/AGENTS.md.starter"
  cmp "$PROJ/src/platform/error.rs" "$TPL/src/platform/error.rs"
  cmp "$PROJ/openapi.json" "$TPL/openapi.json"
  cmp "$PROJ/.claude/agent-config.json" "$TPL/.claude/agent-config.json"
  cmp "$PROJ/db/roles.sql" "$TPL/db/roles.sql"
  cmp "$PROJ/build.rs" "$TPL/build.rs"
  cmp "$PROJ/.claude/rules/backend/postgres.md" "$TPL/.claude/rules/backend/postgres.md"
  cmp "$PROJ/scripts/check/rust-source.mjs" "$TPL/scripts/check/rust-source.mjs"
  [ -x "$PROJ/.githooks/pre-commit" ]
  [ ! -e "$PROJ/package.json" ]
  [ ! -e "$PROJ/.github/workflows/quality-gate.yml" ]
  [ ! -e "$PROJ/.github/workflows/deepseek-review.yml" ]
  [ -f "$PROJ/.github/PULL_REQUEST_TEMPLATE/dev.md" ]
  grep -qx '/target' "$PROJ/.gitignore"
  grep -qx '### Rust + Axum service (agent-be-axum)' "$PROJ/CLAUDE.md"
  run -0 python3 - "$PROJ" <<'PY'
import json, sys
s = json.load(open(sys.argv[1] + "/.claude/settings.json"))
assert "hooks" not in s, sorted(s)
assert "Bash(cargo clippy --locked:*)" in s["permissions"]["allow"], s["permissions"]["allow"]
assert "Bash(cargo install:*)" in s["permissions"]["ask"], s["permissions"]["ask"]
lock = json.load(open(sys.argv[1] + "/.claude/agent-config-kit.lock"))
me = lock["plugins"]["agent-be-axum"]
assert me["stack"] == "be-axum" and me["answers"]["migrations"] == "yes", me
assert "src/main.rs" in me["seeded"] and "Cargo.toml" in me["seeded"], me["seeded"]
print("ok")
PY
}

@test "right after setup, sync --check is in sync" {
  ax_setup
  run --separate-stderr "$SYNC_BIN" check "${ARGS[@]}"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "${lines[${#lines[@]} - 1]}" == "result: in sync (0 findings; exit 0)" ]] || false
}

@test "an existing crate keeps its Cargo.toml and main.rs and gets the by-hand snippet line" {
  rm -rf "$PROJ"
  make_project crate
  ax_args
  local before
  before="$(shasum -a 256 "$PROJ/Cargo.toml" "$PROJ/src/main.rs")"
  ax_setup
  [ "$(shasum -a 256 "$PROJ/Cargo.toml" "$PROJ/src/main.rs")" = "$before" ]
  grep -qE '^  keep +Cargo\.toml +\(exists; left alone; compare with agent-be-axum templates/be-axum/Cargo\.toml\.starter\)$' <<<"$PLAN"
  grep -qE '^  keep +src/main\.rs ' <<<"$PLAN"
  grep -qE '^  by-hand +Cargo\.toml ' <<<"$PLAN"
}

@test "migrations=no leaves the guard configuration and the migration linter out" {
  ax_setup --answer migrations=no --answer pr-templates=no --answer deepseek-review=yes
  [ ! -e "$PROJ/.claude/agent-config.json" ]
  [ ! -e "$PROJ/.squawk.toml" ]
  [ ! -e "$PROJ/db/roles.sql" ]
  [ ! -e "$PROJ/.github/PULL_REQUEST_TEMPLATE" ]
  cmp "$PROJ/.github/workflows/deepseek-review.yml" "$TPL/.github/workflows/deepseek-review.yml"
}

@test "the installed repo passes agent-core's ai-config check: citations resolve, context in budget" {
  ax_setup
  git -C "$PROJ" add -A
  # shellcheck disable=SC2016 # $1 expands in the child shell
  run -0 --separate-stderr bash -c 'cd "$1" && bash scripts/check/ai-config.sh' _ "$PROJ"
  [[ "$output" == *"All cited rule numbers are defined in AGENTS.md"* ]] || false
  [[ "$output" == *"AI config within budget"* ]] || false
}

@test "a repo already set up with another primary stack is refused" {
  mkdir -p "$PROJ/.claude"
  printf '{"plugins": {"agent-be-hono": {"stack": "be-hono", "version": "1.0.0"}}}\n' \
    >"$PROJ/.claude/agent-config-kit.lock"
  run -3 --separate-stderr "$SETUP_BIN" plan "${ARGS[@]}"
  [[ "$stderr" == *"agent-be-axum conflicts with agent-be-hono"* ]] || false
}
