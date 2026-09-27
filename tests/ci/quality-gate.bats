#!/usr/bin/env bats
# actions/quality-gate: plan.sh (inputs, base, package manager, toolchains) and gate.sh end to end
# on toy repositories, with the package manager, uv and gitleaks stubbed. Each failure case proves
# the gate says no, not only that it says yes.

load helpers

setup() {
  ci_isolate
  need_node
  REPO="$BATS_TEST_TMPDIR/repo"
  toy_repo "$REPO"
  stub_tools npm bun uv gitleaks
  cd "$REPO" || return 1
}

gate() { # runs the gate for $QG_STACK (default fe-nextjs-static) against origin/dev
  QG_STACK="${QG_STACK:-fe-nextjs-static}" QG_BASE="${QG_BASE:-dev}" run --separate-stderr bash "$QG/gate.sh"
}

plan() {
  run --separate-stderr bash "$QG/plan.sh"
}

# ── plan.sh ─────────────────────────────────────────────────────────────────────────────────

@test "plan: a valid call prints the stack, base, package manager and toolchains" {
  QG_STACK=fe-nextjs QG_BASE_REF=dev plan
  [ "$status" -eq 0 ]
  [[ "$output" == *"stack=fe-nextjs"* ]]
  [[ "$output" == *"base=origin/dev"* ]]
  [[ "$output" == *"pm=npm"* ]]
  [[ "$output" == *"bun=false"* ]]
  [[ "$output" == *"uv=false"* ]]
}

@test "plan: bun.lock picks bun and asks for setup-bun; pnpm asks for corepack" {
  rm package-lock.json && : >bun.lock
  QG_STACK=be-hono QG_BASE_REF=dev plan
  [ "$status" -eq 0 ]
  [[ "$output" == *"pm=bun"* && "$output" == *"bun=true"* ]]
  QG_STACK=be-hono QG_BASE_REF=dev QG_PACKAGE_MANAGER=pnpm plan
  [[ "$output" == *"pm=pnpm"* && "$output" == *"corepack=true"* ]]
}

@test "plan: an unknown stack, threshold, package manager or strict value exits 2" {
  QG_STACK=rails QG_BASE_REF=dev plan
  [ "$status" -eq 2 ] && [[ "$stderr" == *"stack must be one of"* ]]
  QG_STACK=fe-nextjs QG_BASE_REF=dev QG_COVERAGE_THRESHOLD=101 plan
  [ "$status" -eq 2 ] && [[ "$stderr" == *"coverage-threshold"* ]]
  QG_STACK=fe-nextjs QG_BASE_REF=dev QG_PACKAGE_MANAGER=deno plan
  [ "$status" -eq 2 ]
  QG_STACK=ai-fastapi QG_BASE_REF=dev QG_PACKAGE_MANAGER=npm plan
  [ "$status" -eq 2 ] && [[ "$stderr" == *"ai-fastapi runs on uv"* ]]
  QG_STACK=fe-nextjs QG_BASE_REF=dev QG_STRICT=yes plan
  [ "$status" -eq 2 ]
}

@test "plan: a base that cannot be resolved exits 2 and says how to fix it" {
  QG_STACK=fe-nextjs QG_BASE_REF=prod plan
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"base 'prod' not found"* ]]
  QG_STACK=fe-nextjs QG_BASE_REF=--output=x plan
  [ "$status" -eq 2 ]
}

@test "plan: a changed skill asks for uv (the SkillSpector install needs it)" {
  printf 'PINNED_REF="%s"\n' "$(printf '0%.0s' {1..40})" >scripts/check/skills.sh
  toy_commit "$REPO" "skills.sh"
  git update-ref refs/remotes/origin/dev HEAD
  mkdir -p .claude/skills/tidy && printf -- '---\nname: tidy\n---\n' >.claude/skills/tidy/SKILL.md
  toy_commit "$REPO" skill
  QG_STACK=fe-nextjs QG_BASE_REF=dev plan
  [ "$status" -eq 0 ]
  [[ "$output" == *"uv=true"* ]]
}

@test "plan: writes to GITHUB_OUTPUT on a runner" {
  export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/out"
  QG_STACK=docs-nextra QG_BASE_REF=dev plan
  [ "$status" -eq 0 ]
  grep -qx 'stack=docs-nextra' "$GITHUB_OUTPUT"
  grep -qx 'base=origin/dev' "$GITHUB_OUTPUT"
}

# ── gate.sh ─────────────────────────────────────────────────────────────────────────────────

@test "gate: a clean pull request passes the full fe-nextjs-static gate" {
  printf 'process.exit(0)\n' >scripts/check/site-audit.mjs
  printf 'export const about = () => "about";\n' >src/about.ts
  toy_commit "$REPO" about
  gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"Full gate passed."* ]]
  [[ "$output" == *"gates.sh ran (GATES_PM=npm)"* ]]
  grep -q '^npm ci --no-audit --no-fund --ignore-scripts$' "$STUB_LOG"
  grep -q '^npm run build$' "$STUB_LOG"
  grep -q '^gitleaks git . --no-banner --redact --log-opts=origin/dev..HEAD$' "$STUB_LOG"
}

@test "gate: ignore-scripts false installs with lifecycle scripts" {
  printf 'process.exit(0)\n' >scripts/check/site-audit.mjs
  toy_commit "$REPO" audit
  QG_IGNORE_SCRIPTS=false gate
  [ "$status" -eq 0 ]
  grep -q '^npm ci --no-audit --no-fund$' "$STUB_LOG"
}

@test "gate: a committed .env fails it; a .env*.example template does not" {
  printf 'process.exit(0)\n' >scripts/check/site-audit.mjs
  printf 'API_URL=http://localhost\n' >.env.ci.example
  toy_commit "$REPO" example
  gate
  [ "$status" -eq 0 ]
  printf 'TOKEN=x\n' >.env.local
  toy_commit "$REPO" "real env"
  gate
  [ "$status" -eq 1 ]
  [[ "$output" == *".env.local"* ]]
  [[ "$output" == *"a .env file is committed"* ]]
}

@test "gate: an added eval in app code fails it; in a test file or a removed line it does not" {
  printf 'process.exit(0)\n' >scripts/check/site-audit.mjs
  printf 'const v = eval("1+1");\n' >src/page.test.ts
  toy_commit "$REPO" "test file"
  gate
  [ "$status" -eq 0 ]
  printf 'export const run = (s: string) => eval(s);\n' >src/run.ts
  toy_commit "$REPO" "eval"
  gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"src/run.ts:1:"* ]]
  [[ "$output" == *"Dangerous JS APIs Check found a match"* ]]
}

@test "gate: a removed eval line is not a finding" {
  printf 'process.exit(0)\n' >scripts/check/site-audit.mjs
  printf 'export const run = (s: string) => eval(s);\n' >src/run.ts
  toy_commit "$REPO" "old eval"
  git update-ref refs/remotes/origin/dev HEAD
  rm src/run.ts
  toy_commit "$REPO" "remove eval"
  gate
  [ "$status" -eq 0 ]
}

@test "gate: dangerouslySetInnerHTML and javascript: URLs added in app code fail it" {
  printf 'process.exit(0)\n' >scripts/check/site-audit.mjs
  printf 'export const A = () => <div dangerouslySetInnerHTML={{ __html: x }} />;\n' >src/a.tsx
  printf 'export const href = "javascript:alert(1)";\n' >src/b.ts
  toy_commit "$REPO" "unsafe"
  gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unsafe React Patterns Check found a match"* ]]
  [[ "$output" == *"URL Scheme Injection Check found a match"* ]]
}

@test "gate: on a runner, text from the diff is printed with workflow commands switched off" {
  printf 'process.exit(0)\n' >scripts/check/site-audit.mjs
  printf 'export const x = eval("::add-mask::y");\n' >src/x.ts
  toy_commit "$REPO" "command text"
  GITHUB_ACTIONS=true gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"::stop-commands::qg"* ]]
}

@test "gate: gitleaks findings fail it" {
  printf 'process.exit(0)\n' >scripts/check/site-audit.mjs
  toy_commit "$REPO" audit
  STUB_GITLEAKS_EXIT=1 gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"gitleaks found a secret"* ]]
}

@test "gate: without gitleaks a strict gate fails, and a non-strict one passes as partial" {
  printf 'process.exit(0)\n' >scripts/check/site-audit.mjs
  toy_commit "$REPO" audit
  rm "$STUBS/gitleaks"
  PATH="$(path_without gitleaks)" gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"Secret Scan (gitleaks) did not run"* ]]
  [[ "$output" == *"the gate was partial and strict is on"* ]]
  QG_STRICT=false PATH="$(path_without gitleaks)" gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"PARTIAL"* ]]
}

@test "gate: a failing gates.list, build or site audit fails it" {
  printf 'process.exit(Number(process.env.SITE_AUDIT_EXIT || 0))\n' >scripts/check/site-audit.mjs
  toy_commit "$REPO" audit
  TOY_GATES_EXIT=1 gate
  [ "$status" -eq 1 ] && [[ "$output" == *"a gate in scripts/check/gates.list failed"* ]]
  STUB_NPM_EXIT=1 gate
  [ "$status" -eq 1 ] && [[ "$output" == *"Install Dependencies failed"* ]]
  SITE_AUDIT_EXIT=1 gate
  [ "$status" -eq 1 ] && [[ "$output" == *"the built site failed a check"* ]]
}

@test "gate: no gates.list or site-audit.mjs is a check that did not run" {
  rm scripts/check/gates.list
  toy_commit "$REPO" "no list"
  gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"Repo Gates did not run"* ]]
  [[ "$output" == *"Built Site Audit did not run"* ]]
}

@test "gate: the coverage floor reads the report the gates wrote" {
  printf 'process.exit(0)\n' >scripts/check/site-audit.mjs
  toy_commit "$REPO" audit
  TOY_LCOV="$(lcov 10 10 2 2)" QG_COVERAGE_THRESHOLD=100 gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"lines"*"10 / 10"*"ok"* ]]
  TOY_LCOV="$(lcov 10 9 2 2)" QG_COVERAGE_THRESHOLD=100 gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"coverage is below the 100% floor"* ]]
  TOY_LCOV="$(lcov 10 9 2 2)" QG_COVERAGE_THRESHOLD=90 gate
  [ "$status" -eq 0 ]
}

@test "gate: a floor with no coverage report did not run; threshold 0 turns it off" {
  printf 'process.exit(0)\n' >scripts/check/site-audit.mjs
  toy_commit "$REPO" audit
  QG_COVERAGE_THRESHOLD=100 gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"Coverage Floor did not run"* ]]
  QG_COVERAGE_THRESHOLD=0 gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"coverage-threshold is 0"* ]]
}

@test "gate: the env file exports dummies by name, keeps the environment's values, refuses PATH" {
  printf 'process.exit(process.env.API_URL === "http://ci" && process.env.KEEP === "mine" ? 0 : 3)\n' >scripts/check/site-audit.mjs
  printf '# dummies\nAPI_URL="http://ci"\nexport KEEP=theirs\n' >.env.ci.example
  toy_commit "$REPO" env
  KEEP=mine gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"loaded 1 variable(s) from .env.ci.example: API_URL"* ]]
  [[ "$output" == *"kept: KEEP"* ]]
  [[ "$output" != *"http://ci"* ]]
  printf 'PATH=/tmp/evil\n' >.env.ci.example
  gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"PATH changes how the runner"* ]]
  QG_ENV_FILE=.env.ci gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be a committed *.example file"* ]]
}

@test "gate: a bad stack, threshold or base exits 2 before any check" {
  QG_STACK=rails gate
  [ "$status" -eq 2 ]
  QG_COVERAGE_THRESHOLD=abc gate
  [ "$status" -eq 2 ]
  QG_BASE=nope gate
  [ "$status" -eq 2 ]
  [ ! -s "$STUB_LOG" ]
}

@test "gate: with agent-core's real gates.sh, the floor finds vitest's report in the gates log folder" {
  local real="$KIT_ROOT/plugins/agent-core/templates/common/scripts/check/gates.sh"
  [ -f "$real" ] || skip "agent-core's gates.sh template is not built"
  cp "$real" scripts/check/gates.sh
  printf 'code\tnpm run test:coverage\n' >scripts/check/gates.list
  printf '{\n  "name": "toy",\n  "scripts": { "build": "next build", "test:coverage": "vitest run --coverage" }\n}\n' >package.json
  printf 'process.exit(0)\n' >scripts/check/site-audit.mjs
  toy_commit "$REPO" "vitest"
  # npm stub: `npm run test:coverage -- --coverage.reportsDirectory=DIR` writes an istanbul report
  # to DIR, as vitest does; every other call just succeeds.
  cat >"$STUBS/npm" <<'EOF'
#!/usr/bin/env bash
printf 'npm %s\n' "$*" >>"$STUB_LOG"
for a in "$@"; do
  case "$a" in --coverage.reportsDirectory=*)
    d="${a#*=}" && mkdir -p "$d"
    printf '{"/src/a.ts":{"statementMap":{"0":{"start":{"line":1}}},"s":{"0":%s},"f":{},"b":{}}}\n' "${TOY_HITS:-1}" >"$d/coverage-final.json"
    ;;
  esac
done
exit 0
EOF
  chmod +x "$STUBS/npm"
  QG_COVERAGE_THRESHOLD=100 gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"/gates/"*"/coverage/coverage-final.json (floor 100%)"* ]]
  grep -q -- '^npm run test:coverage -- --coverage.reportsDirectory=' "$STUB_LOG"
  TOY_HITS=0 QG_COVERAGE_THRESHOLD=100 gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"coverage is below the 100% floor"* ]]
}

# ── be-hono ─────────────────────────────────────────────────────────────────────────────────

be_hono_repo() {
  rm package-lock.json && : >bun.lock
  mkdir -p src/db/client
  printf '#!/usr/bin/env bash\necho migrations clean\n' >scripts/check/migrations.sh
  printf '#!/usr/bin/env bash\necho indexes clean\n' >scripts/check/index-coverage.sh
  cat >src/app.ts <<'EOF'
app.use(requestId());
app.use(secureHeaders());
// app.use(cors());
app.use('/api/*', bodyLimit({ maxSize: 1024 }), timeout(5000));
app.use(cors({ origin: env.CORS_ORIGINS }));
EOF
  cat >src/db/client/index.ts <<'EOF'
export const sql = postgres(url, { max: 10, connection: { statement_timeout: 5000, idle_in_transaction_session_timeout: 5000 } });
EOF
  toy_commit "$REPO" "be layout"
}

@test "gate: be-hono passes with the hardened app and runs its migration and index checks" {
  be_hono_repo
  QG_STACK=be-hono QG_COVERAGE_THRESHOLD=0 gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"migrations clean"* && "$output" == *"indexes clean"* ]]
  grep -q '^bun install --frozen-lockfile --ignore-scripts$' "$STUB_LOG"
  grep -q '^bun run build$' "$STUB_LOG"
}

@test "gate: be-hono fails a bare cors(), a missing middleware and a pool cap of 1" {
  be_hono_repo
  sed -e 's/cors({ origin: env.CORS_ORIGINS })/cors()/' -e '/secureHeaders/d' src/app.ts >src/app.new && mv src/app.new src/app.ts
  sed -e 's/max: 10/max: 1/' src/db/client/index.ts >src/db/client/new.ts && mv src/db/client/new.ts src/db/client/index.ts
  toy_commit "$REPO" "weaker"
  QG_STACK=be-hono QG_COVERAGE_THRESHOLD=0 gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"bare cors()"* ]]
  [[ "$output" == *"the secureHeaders middleware is missing"* ]]
  [[ "$output" == *"a pool cap of 1 or 2"* ]]
  [[ "$output" != *"the requestId middleware is missing"* ]]
}

# ── ai-fastapi ──────────────────────────────────────────────────────────────────────────────

@test "gate: ai-fastapi installs with uv, reads coverage.py's floor, and runs integration tests on request" {
  rm package.json package-lock.json
  : >.coverage
  toy_commit "$REPO" "python"
  QG_STACK=ai-fastapi gate
  [ "$status" -eq 0 ]
  grep -q '^uv sync --frozen$' "$STUB_LOG"
  grep -q '^uv run --frozen coverage report --fail-under=100$' "$STUB_LOG"
  [[ "$output" == *"integration-tests is off"* ]] || false
  run ! grep -q -- '-m integration' "$STUB_LOG"
  QG_STACK=ai-fastapi QG_INTEGRATION_TESTS=true gate
  [ "$status" -eq 0 ]
  grep -q '^uv run --frozen pytest tests -q -m integration$' "$STUB_LOG"
}

@test "gate: ai-fastapi fails below the floor (coverage report exits 2)" {
  rm package.json package-lock.json
  : >.coverage
  toy_commit "$REPO" "python"
  STUB_UV_EXIT=2 QG_STACK=ai-fastapi gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"coverage is below the 100% floor"* ]]
}
