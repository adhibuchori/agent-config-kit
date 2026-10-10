#!/usr/bin/env bats
# The be-go template: setup.json, the rule index and its citations, the gate list, the shared copies,
# the PostgreSQL files both backends ship, the seeded skeleton's size and the CI callers.
# Read-only checks against this repository.

load helpers

setup() {
  go_setup_env
}

@test "setup.json is strict JSON, names this stack, and conflicts with every other primary stack" {
  jq empty "$TPL/_kit/setup.json"
  run jq -r '.stack' "$TPL/_kit/setup.json"
  [ "$output" = be-go ]
  run jq -r '.conflictsWith | sort | join(" ")' "$TPL/_kit/setup.json"
  [ "$output" = "$CONFLICTS" ]
  run jq -r '.snippets["go.mod"]' "$TPL/_kit/setup.json"
  [ "$output" = snippets/go.mod.tools ]
  [ -f "$TPL/_kit/snippets/go.mod.tools" ]
  run jq -r '.packageScripts | length' "$TPL/_kit/setup.json"
  [ "$output" = 0 ]
}

@test "every JSON file in the template is strict JSON" {
  local f
  while IFS= read -r -d '' f; do
    jq empty "$f"
  done < <(find "$TPL" -name '*.json' -print0)
}

@test "AGENTS.md.starter defines rules 1 to 32, each with an enforcer and a detail file" {
  run grep -cE '^\| [0-9]+ \| .+ \| .+ \| `[^`]+` \|$' "$TPL/AGENTS.md.starter"
  [ "$output" = 32 ]
  local n
  for n in $(seq 1 32); do
    grep -qE "^\| $n \| " "$TPL/AGENTS.md.starter"
  done
}

@test "every Rule N the template cites is a rule AGENTS.md.starter defines" {
  local cited n
  cited="$(grep -rhoE 'Rules? [0-9]+([–-][0-9]+)?' "$TPL" --include='*.md' --include='*.sh' --include='*.yml' \
    --include='*.yaml' --include='*.go' --include='*.list' | grep -oE '[0-9]+' | sort -un)"
  [ -n "$cited" ]
  for n in $cited; do
    grep -qE "^\| $n \| " "$TPL/AGENTS.md.starter" || {
      echo "Rule $n is cited but not defined" >&2
      return 1
    }
  done
}

@test "every file the rule index names as its detail is installed by this plugin or agent-core" {
  local f
  while IFS= read -r f; do
    [ -f "$TPL/$f" ] || [ -f "$CORE_TPL/$f" ] || [ "$f" = .claude/rules/go/types.md ] || {
      echo "the index points at $f, which nothing installs" >&2
      return 1
    }
  done < <(sed -nE 's/^\| [0-9]+ \|.*\| `([^`]+)` \|$/\1/p' "$TPL/AGENTS.md.starter" | sort -u)
}

@test "gates.list calls only scripts the template or agent-core installs, and no @format" {
  local script
  run grep -cE '^[^#].*@format' "$TPL/scripts/check/gates.list"
  [ "$output" = 0 ]
  while IFS= read -r script; do
    [ -f "$TPL/$script" ] || [ -f "$CORE_TPL/$script" ] || {
      echo "gates.list runs $script, which nothing installs" >&2
      return 1
    }
  done < <(grep -v '^#' "$TPL/scripts/check/gates.list" | grep -oE 'scripts/check/[A-Za-z0-9._-]+' | sort -u)
  grep -qx $'code\tbash scripts/check/ci-env.sh bash scripts/check/coverage.sh' "$TPL/scripts/check/gates.list"
}

@test "the shared scripts are byte copies: coverage-policy.mjs and ci-env.sh as agent-be-hono ships them" {
  cmp "$TPL/scripts/check/coverage-policy.mjs" "$KIT_ROOT/plugins/agent-be-hono/templates/be-hono/scripts/check/coverage-policy.mjs"
  cmp "$TPL/scripts/check/ci-env.sh" "$KIT_ROOT/plugins/agent-be-hono/templates/be-hono/scripts/check/ci-env.sh"
}

@test "the files both backends ship are identical to agent-be-axum's, when it is built" {
  local axum="$KIT_ROOT/plugins/agent-be-axum/templates/be-axum" f
  [ -d "$axum" ] || skip "agent-be-axum is not built in this checkout"
  for f in .claude/rules/backend/postgres.md db/roles.sql scripts/check/coverage-per-file.mjs \
    $(cd "$TPL" && ls .claude/anti-patterns/{cic-retry-keeps-invalid-index,cic-inside-transaction,session-state-behind-transaction-pooler,pgbouncer-rejects-startup-parameters,cached-plan-after-schema-change,default-privileges-without-for-role,read-only-default-is-not-a-boundary,enum-value-used-in-same-transaction,ddl-without-lock-timeout,unindexed-foreign-keys}.md); do
    cmp "$TPL/$f" "$axum/$f"
  done
}

@test "the PostgreSQL files both backends ship say nothing specific to Go" {
  local f
  for f in .claude/rules/backend/postgres.md db/roles.sql .claude/anti-patterns/cic-retry-keeps-invalid-index.md \
    .claude/anti-patterns/cic-inside-transaction.md .claude/anti-patterns/session-state-behind-transaction-pooler.md \
    .claude/anti-patterns/pgbouncer-rejects-startup-parameters.md .claude/anti-patterns/cached-plan-after-schema-change.md \
    .claude/anti-patterns/default-privileges-without-for-role.md .claude/anti-patterns/read-only-default-is-not-a-boundary.md \
    .claude/anti-patterns/enum-value-used-in-same-transaction.md .claude/anti-patterns/ddl-without-lock-timeout.md \
    .claude/anti-patterns/unindexed-foreign-keys.md; do
    run grep -nEi 'goose|pgx|sqlc|golang|go test|\.go\b|apperr|internal/httpapi|Rule [0-9]' "$TPL/$f"
    [ "$status" -eq 1 ] || {
      echo "$f: $output" >&2
      return 1
    }
  done
}

@test "the anti-pattern index lists every anti-pattern file, and only those" {
  local f listed
  listed="$(grep -oE '\| [a-z0-9-]+\.md \|$' "$TPL/.claude/anti-patterns/INDEX.md" | tr -d '| ' | sort)"
  [ "$(printf '%s\n' "$listed" | wc -l | tr -d ' ')" = 17 ]
  [ "$listed" = "$(cd "$TPL/.claude/anti-patterns" && ls | grep -v '^INDEX\.md$' | sort)" ]
}

@test "every rule file loads only for the paths it covers" {
  local f
  while IFS= read -r -d '' f; do
    [ "$(head -1 "$f")" = "---" ]
    sed -n '2,/^---$/p' "$f" | grep -q '^paths:'
  done < <(find "$TPL/.claude/rules" -name '*.md' -print0)
}

@test "the seeded Go files stay at 200 code lines or fewer; generated files aside" {
  local f n
  while IFS= read -r -d '' f; do
    grep -qE '^// Code generated .* DO NOT EDIT\.$' "$f" && continue
    n="$(code_lines "$f")"
    [ "$n" -le 200 ] || {
      echo "$f: $n code lines" >&2
      return 1
    }
  done < <(find "$TPL" -name '*.go' -print0)
}

@test "every seeded Go file other than generated code stays thin: no route literal" {
  run grep -rnE '["`]/api(/|["`])' "$TPL/internal" "$TPL/cmd" --include='*.go' --exclude='*_test.go' --exclude='*.gen.go'
  [ "$status" -eq 1 ]
}

@test "the problem-type base is the same placeholder in the code and in the spec" {
  grep -q '^const TypeBase = "https://example.invalid/problems/"$' "$TPL/internal/apperr/types.go"
  grep -qE '^ +x-problem-type-base: https://example.invalid/problems/$' "$TPL/api/openapi.yaml"
  grep -q '"x-problem-type-base": "https://example.invalid/problems/"' "$TPL/api/openapi.json"
}

@test "settings.json allows named scripts and named commands only; runners ask first" {
  run -0 python3 - "$TPL/.claude/settings.json" <<'PY'
import json, re, sys
s = json.load(open(sys.argv[1]))
assert set(s) <= {"$schema", "permissions"}, sorted(s)
broad = re.compile(r"^Bash\((go (run|generate|get|install)|go tool goose|go tool govulncheck|docker( compose)?|bash|sh|node|python3?)(:\*|\s\*)?\)$")
for rule in s["permissions"]["allow"]:
    assert not broad.match(rule), rule
    assert rule.startswith("Bash("), rule
for rule in ("Bash(go run:*)", "Bash(go generate:*)", "Bash(go get:*)", "Bash(go install:*)"):
    assert rule in s["permissions"]["ask"], rule
print("ok")
PY
}

@test "the CI callers: the quality gate held at the release placeholder with its inputs, DeepSeek pinned" {
  local qg="$TPL/.github/workflows/quality-gate.yml"
  grep -qE '^    uses: adhibuchori/agent-config-kit/\.github/workflows/be-go-quality-gate\.yml@0{40} # v[0-9]+\.[0-9]+\.[0-9]+$' "$qg"
  grep -qE '^      database: true$' "$qg"
  grep -qE '^      pgbouncer-tests: false$' "$qg"
  grep -qE '^      pgbouncer-max-prepared-statements: 200$' "$qg"
  grep -qE '^  pull_request:$' "$qg"
  run grep -nE '^\s*(push|schedule|pull_request_target):' "$qg" "$TPL/.github/workflows/deepseek-review.yml"
  [ "$status" -eq 1 ]
  grep -qE 'deepseek-review\.yml@[0-9a-f]{40} # v[0-9]+\.[0-9]+\.[0-9]+$' "$TPL/.github/workflows/deepseek-review.yml"
}

@test ".env.ci.example names the test databases without a password" {
  grep -qx 'TEST_DATABASE_URL=postgres://app_rw@127.0.0.1:5432/app_test?sslmode=disable' "$TPL/.env.ci.example"
  grep -qx 'TEST_POOLER_DATABASE_URL=postgres://app_rw@127.0.0.1:6432/app_test?sslmode=disable' "$TPL/.env.ci.example"
  run grep -nE '://[^@/]+:[^@/]+@' "$TPL/.env.ci.example"
  [ "$status" -eq 1 ]
}

@test "the scripts setup installs are executable, parse under bash 3.2 and pass shellcheck when present" {
  local f
  for f in "$TPL"/scripts/check/*.sh "$TPL/.githooks/pre-commit"; do
    [ -x "$f" ]
    /bin/bash -n "$f"
  done
  command -v shellcheck >/dev/null || skip "shellcheck is not installed"
  shellcheck -x -S style "$TPL"/scripts/check/*.sh "$TPL/.githooks/pre-commit"
}

@test "the template ships no file setup refuses: package.json, .gitignore, a real CLAUDE.md or AGENTS.md" {
  [ ! -e "$TPL/package.json" ]
  [ ! -e "$TPL/.gitignore" ]
  [ ! -e "$TPL/CLAUDE.md" ]
  [ ! -e "$TPL/AGENTS.md" ]
  [ ! -e "$TPL/go.mod" ]
  [ -f "$TPL/go.mod.starter" ]
  [ ! -d "$TPL/.claude/hooks" ] && [ ! -d "$TPL/.claude/commands" ] && [ ! -d "$TPL/.claude/skills" ]
}

@test "go.mod.starter pins the tools as go.mod tool lines and a fixed golang.org/x/text" {
  local mod="$TPL/go.mod.starter"
  grep -qx 'module example.com/service' "$mod"
  grep -qx 'go 1.27.0' "$mod"
  local tool
  for tool in github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen github.com/sqlc-dev/sqlc/cmd/sqlc \
    github.com/pressly/goose/v3/cmd/goose golang.org/x/vuln/cmd/govulncheck; do
    grep -qx $'\t'"$tool" "$mod"
  done
  grep -qF $'\tgithub.com/oapi-codegen/oapi-codegen/v2 v2.8.0' "$mod"
  grep -qF $'\tgithub.com/sqlc-dev/sqlc v1.31.1' "$mod"
  grep -qF $'\tgithub.com/pressly/goose/v3 v3.28.0' "$mod"
  grep -qF $'\tgolang.org/x/vuln v1.8.0' "$mod"
  grep -qx $'\tgithub.com/jackc/pgx/v5 v5.11.0' "$mod"
  run python3 -c 'import re, sys; v = re.search(r"golang.org/x/text v0\.(\d+)\.", open(sys.argv[1]).read()); print(int(v.group(1)))' "$mod"
  [ "$output" -ge 41 ]
}

# ── the payload contract (payload-encryption) ─────────────────────────────────────────────────

@test "payload: the contract, its short rule and the vectors are byte copies of agent-be-hono's" {
  local hono="$KIT_ROOT/plugins/agent-be-hono/templates/be-hono" f
  for f in .claude/PAYLOAD-CONTRACT.md .claude/rules/common/payload-contract.md scripts/check/payload-vectors.json; do
    cmp "$TPL/$f" "$hono/$f"
  done
}

@test "payload: payload.config.json is the Go shape the shared registry check reads" {
  run jq -c . "$TPL/payload.config.json"
  [ "$output" = '{"encryption":"strict","spec":"api/openapi.json","registry":"internal/payload/registry.gen.go","language":"go","handshake":"getPayloadHandshake","exemptions":{},"peers":[]}' ]
}

@test "payload: the seeded registry is what the generator writes for the seeded spec" {
  command -v node >/dev/null || skip "node is not installed"
  local dir="$BATS_TEST_TMPDIR/gen" f
  for f in api/openapi.json payload.config.json scripts/lib/payload-registry.mjs scripts/generate/payload-registry.mjs; do
    mkdir -p "$dir/$(dirname "$f")"
    cp "$TPL/$f" "$dir/$f"
  done
  run node "$dir/scripts/generate/payload-registry.mjs"
  [ "$status" -eq 0 ]
  cmp "$dir/internal/payload/registry.gen.go" "$TPL/internal/payload/registry.gen.go"
}

@test "payload: every file the question installs exists, only yes installs them, and the why names the steps" {
  run python3 - "$TPL" <<'PY'
import glob, json, os, sys
tpl = sys.argv[1]
q = [q for q in json.load(open(tpl + "/_kit/setup.json"))["questions"] if q["id"] == "payload-encryption"][0]
assert q["choices"] == ["yes", "no"] and q["recommended"] == "no" and set(q["install"]) == {"yes"}, q
for g in q["install"]["yes"]:
    assert glob.glob(os.path.join(tpl, g), recursive=True), g
assert q["settings"] == {"yes": {"/permissions/deny": ["Bash(node scripts/generate/payload-server-key.mjs:*)"]}}, q
for step in ("Registered()", "Problem.code", "GET /api/payload/handshake", "NewRouter", "stay red"):
    assert step in q["why"], step
print("ok")
PY
  [ "$output" = ok ]
}

@test "payload: the Go rule covers rules 28 to 32 and the wiring the gates wait for" {
  local f="$TPL/.claude/rules/backend/go-payload.md" n
  for n in 28 29 30 31 32; do
    grep -q "(Rule $n)" "$f"
  done
  grep -qF 'chain = sealBodies(chain, edge, payload.Registry(), logger)' "$f"
  grep -qF 'enum: [strict, "off"]' "$f"
}
