# shellcheck shell=bash
# Shared by plan.sh, gate.sh and stacks/*.sh of the agent-config-kit quality gate action.
#
# The gate's contract: every check either passes, fails, or is recorded as a check that did NOT run.
# With strict on (the default on a runner), a check that did not run fails the gate too, because a
# gate that quietly skipped its secret scan reads exactly like one that passed it.
#
# bash 3.2 compatible (a macOS self-hosted runner has only /bin/bash 3.2): no associative arrays,
# no mapfile, and empty arrays expand as ${a[@]+"${a[@]}"}.

QG_FAILED=0
QG_SKIPPED=""
QG_STACKS="fe-nextjs fe-nextjs-static be-hono ai-fastapi docs-nextra be-go be-axum ios-swiftui"

# The names an env file may not set, because they change how the runner, git or a toolchain behaves
# (GOFLAGS, CARGO_HOME, RUSTFLAGS, SQLX_OFFLINE, DEVELOPER_DIR, ...). GO alone or GO followed by
# letters and digits is Go's own; GOOGLE_CLIENT_ID is not. One extended regex, the same bytes as
# REFUSED in each stack's scripts/check/ci-env.sh (tests/ci/quality-gate.bats compares them).
QG_REFUSED_ENV='^(PATH|HOME|SHELL|ENV|BASH_ENV|IFS|CDPATH|PS4|TMPDIR|CI|LD_.*|DYLD_.*|NODE_OPTIONS|NODE_PATH|PYTHON.*|GITHUB_.*|RUNNER_.*|ACTIONS_.*|GIT_.*|BUN_.*|NPM_CONFIG_.*|UV_.*|QG_.*|GO[A-Z0-9]*|GO_.*|GOROOT_.*|CGO_.*|CARGO_.*|RUSTUP_.*|RUSTC.*|RUSTDOCFLAGS|RUSTFLAGS|SQLX_.*|DEVELOPER_DIR)$'

# The be-go and be-axum workflows start PostgreSQL 18.6 as a service on 127.0.0.1:5432 with trust
# auth, so no password exists anywhere. The gate's own database steps connect as its superuser; set
# QG_PG_ADMIN_URL to run them against another server by hand.
QG_PG_ADMIN_URL="${QG_PG_ADMIN_URL:-postgresql://postgres@127.0.0.1:5432/postgres?sslmode=disable}"

# The lines a pull request adds to its own code, for the diff scans: every JavaScript and TypeScript
# file except tests, declarations, the kit's installed check scripts, CI files and content pages,
# which may quote the very patterns the scans refuse. In a git pathspec `*` also matches `/`.
QG_JS_CODE=('*.js' '*.jsx' '*.mjs' '*.cjs' '*.ts' '*.tsx' '*.mts' '*.cts'
  ':(exclude)*.d.ts' ':(exclude)*.test.*' ':(exclude)*.spec.*' ':(exclude)*/__tests__/*'
  ':(exclude)*/testing/*' ':(exclude)scripts/check/*' ':(exclude).github/*' ':(exclude)content/*')

# What SkillSpector scans (scripts/check/skills.sh); the scan runs only when a PR touches one.
QG_SKILL_PATHS=(.agents/skills .claude/skills .claude/commands .claude/agents .claude/hooks
  _workflow-source .skillspector-baseline.yaml scripts/check/skills.sh)

qg_step() {
  printf '\n\033[1m── %s\033[0m\n' "$1"
}

qg_fail() {
  echo "::error::$1"
  QG_FAILED=$((QG_FAILED + 1))
}

qg_skip() {
  echo "::warning::$1 did not run: $2"
  QG_SKIPPED="${QG_SKIPPED}"$'\n'"  $1: $2"
}

# qg_run <name> <command...>: one named check; a non-zero exit fails it.
qg_run() {
  local name="$1"
  shift
  qg_step "$name"
  if ! "$@"; then
    qg_fail "$name failed"
  fi
}

# Prints stdin with workflow commands switched off, for text the pull request controls (file names,
# added lines): a line such as "::add-mask::" in a diff must reach the log as text, not as a command.
qg_quote() {
  if [ "${GITHUB_ACTIONS:-}" != "true" ]; then
    cat
    return
  fi
  local token
  token="qg$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
  echo "::stop-commands::${token}"
  cat
  echo "::${token}::"
}

# qg_is_stack <id>: one of the stacks this action knows.
qg_is_stack() {
  case " $QG_STACKS " in *" $1 "*) return 0 ;; esac
  return 1
}

# qg_default_threshold <stack>: the coverage floor when the caller names none. A content site has
# little logic to cover, and a docs site has no test suite.
qg_default_threshold() {
  case "$1" in
  fe-nextjs-static | docs-nextra) echo 0 ;;
  *) echo 100 ;;
  esac
}

# qg_valid_threshold <n>: a number from 0 to 100 (decimals allowed).
qg_valid_threshold() {
  printf '%s' "$1" | grep -Eq '^(100(\.0+)?|[0-9]{1,2}(\.[0-9]+)?)$'
}

qg_threshold_off() {
  printf '%s' "$1" | grep -Eq '^0+(\.0+)?$'
}

# qg_js_stack <id>: a stack that installs JavaScript dependencies from a lockfile.
qg_js_stack() {
  case "$1" in fe-nextjs | fe-nextjs-static | be-hono | docs-nextra) return 0 ;; esac
  return 1
}

# qg_resolve_base <ref>: the commit the diff checks compare against. A branch name resolves to its
# remote-tracking ref first (a pull-request checkout has origin/<base>, not a local branch).
qg_resolve_base() {
  local ref="$1"
  [ -n "$ref" ] || return 1
  case "$ref" in -*) return 1 ;; esac
  if git rev-parse --verify --quiet "refs/remotes/origin/${ref}^{commit}" >/dev/null; then
    echo "origin/${ref}"
  elif git rev-parse --verify --quiet "${ref}^{commit}" >/dev/null; then
    echo "$ref"
  else
    return 1
  fi
}

# qg_detect_pm: the JavaScript package manager this repo's lockfile names, or "none".
qg_detect_pm() {
  if [ -f bun.lock ] || [ -f bun.lockb ]; then
    echo bun
  elif [ -f pnpm-lock.yaml ]; then
    echo pnpm
  elif [ -f yarn.lock ]; then
    echo yarn
  elif [ -f package-lock.json ] || [ -f npm-shrinkwrap.json ]; then
    echo npm
  else
    echo none
  fi
}

# qg_has_script <name>: package.json declares that script.
qg_has_script() {
  [ -f package.json ] || return 1
  node -e '
    const s = JSON.parse(require("fs").readFileSync("package.json", "utf8")).scripts || {};
    process.exit(Object.prototype.hasOwnProperty.call(s, process.argv[1]) ? 0 : 1);
  ' "$1" 2>/dev/null
}

# qg_pm_run <script>: runs a package.json script with the repo's package manager.
qg_pm_run() {
  case "$QG_PM" in
  bun) bun run "$1" ;;
  pnpm) pnpm run "$1" ;;
  yarn) yarn run "$1" ;;
  *) npm run "$1" ;;
  esac
}

# Installs exactly the lockfile. Lifecycle scripts of dependencies stay off unless ignore-scripts is
# false: the gate runs the pull request's own code, not every package's install hook.
qg_js_install() {
  qg_step "Install Dependencies ($QG_PM)"
  local ignore=()
  [ "${QG_IGNORE_SCRIPTS:-true}" = "true" ] && ignore=(--ignore-scripts)
  local rc=0
  case "$QG_PM" in
  bun) bun install --frozen-lockfile ${ignore[@]+"${ignore[@]}"} || rc=$? ;;
  pnpm) pnpm install --frozen-lockfile ${ignore[@]+"${ignore[@]}"} || rc=$? ;;
  npm) npm ci --no-audit --no-fund ${ignore[@]+"${ignore[@]}"} || rc=$? ;;
  yarn)
    if [ -f .yarnrc.yml ]; then
      if [ "${QG_IGNORE_SCRIPTS:-true}" = "true" ]; then
        yarn install --immutable --mode=skip-build || rc=$?
      else
        yarn install --immutable || rc=$?
      fi
    else
      yarn install --frozen-lockfile ${ignore[@]+"${ignore[@]}"} || rc=$?
    fi
    ;;
  *)
    qg_fail "no lockfile (bun.lock, pnpm-lock.yaml, yarn.lock or package-lock.json): the gate installs exactly a committed lockfile"
    return 1
    ;;
  esac
  if [ "$rc" -ne 0 ]; then
    qg_fail "Install Dependencies failed"
    return 1
  fi
}

# qg_load_env_file <file>: exports the build and test variables a committed *.example file holds
# (KEY=VALUE lines; # comments; one layer of quotes stripped; no expansion). They are dummies that a
# settings module validates at import time, never secrets. A variable the environment already sets
# (a secret the caller passed) keeps its value. Only the names are printed. Variables that would
# change how the runner, git or a toolchain behaves are refused.
qg_load_env_file() {
  local f="$1" line key value names="" kept="" n=0
  [ -n "$f" ] || return 0
  case "$f" in
  *.example) ;;
  *)
    qg_fail "env-file must be a committed *.example file of dummy values, got: $f"
    return 1
    ;;
  esac
  if [ ! -f "$f" ]; then
    echo "env-file: $f is not in this repo; no build or test variables loaded"
    return 0
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in '' | '#'*) continue ;; esac
    line="${line#export }"
    key="${line%%=*}"
    value="${line#*=}"
    if [ "$key" = "$line" ] || ! printf '%s' "$key" | grep -Eq '^[A-Z_][A-Z0-9_]*$'; then
      qg_fail "env-file $f: a line is not KEY=VALUE with an upper-case KEY"
      return 1
    fi
    if printf '%s' "$key" | grep -Eq "$QG_REFUSED_ENV"; then
      qg_fail "env-file $f: $key changes how the runner or a toolchain behaves; the gate refuses it"
      return 1
    fi
    if [ -n "${!key:-}" ]; then
      kept="${kept} ${key}"
      continue
    fi
    case "$value" in
    \"*\") value="${value#\"}" && value="${value%\"}" ;;
    \'*\') value="${value#\'}" && value="${value%\'}" ;;
    esac
    export "${key}=${value}"
    names="${names} ${key}"
    n=$((n + 1))
  done <"$f"
  echo "env-file: loaded $n variable(s) from $f:${names}"
  [ -z "$kept" ] || echo "env-file: already set by the environment, kept:${kept}"
}

# Every gate the repo lists in scripts/check/gates.list (agent-core's gates.sh runs them; the
# pre-commit hook runs the same list on staged files). The list is the repo's own: CI adds only what
# needs a pull request.
qg_gates() {
  qg_step "Repo Gates (scripts/check/gates.list)"
  if [ ! -f scripts/check/gates.sh ] || [ ! -f scripts/check/gates.list ]; then
    qg_skip "Repo Gates" "scripts/check/gates.sh or scripts/check/gates.list is missing: run /agent-core:setup and the stack plugin's setup"
    return
  fi
  mkdir -p "$QG_TMP/gates"
  local pm_env=()
  case "$QG_PM" in bun | pnpm | yarn | npm) pm_env=("GATES_PM=$QG_PM") ;; esac
  if ! env ${pm_env[@]+"${pm_env[@]}"} TMPDIR="$QG_TMP/gates" bash scripts/check/gates.sh </dev/null; then
    qg_fail "a gate in scripts/check/gates.list failed (its last 20 lines are above)"
  fi
}

# The coverage floor, read from the report the tests just wrote (gates.list runs them). The test
# runner's own thresholds still apply; this is the floor the pull request cannot lower by editing
# its config. 0 turns it off.
qg_coverage_floor() {
  qg_step "Coverage Floor (${QG_COVERAGE_THRESHOLD}%)"
  if qg_threshold_off "$QG_COVERAGE_THRESHOLD"; then
    echo "coverage-threshold is 0: no floor (the test runner's own thresholds still apply)"
    return
  fi
  node "$QG_HERE/coverage-floor.mjs" --threshold "$QG_COVERAGE_THRESHOLD" coverage "$QG_TMP/gates"
  case $? in
  0) ;;
  1) qg_fail "coverage is below the ${QG_COVERAGE_THRESHOLD}% floor" ;;
  3) qg_skip "Coverage Floor" "no coverage report (lcov.info, coverage-summary.json, coverage-final.json or Go's coverage.out) under coverage/: run the tests with coverage in scripts/check/gates.list, or pass coverage-threshold: 0" ;;
  *) qg_fail "Coverage Floor could not read the coverage report" ;;
  esac
}

qg_env_committed() {
  qg_step "Check .env Not Committed"
  local changed hits
  if ! changed=$(git diff --name-only --diff-filter=ACMR "${QG_BASE}...HEAD"); then
    qg_fail "could not list the files changed since $QG_BASE"
    return
  fi
  hits=$(printf '%s\n' "$changed" | grep -E '(^|/)\.env(\.|$)' | grep -vE '(^|/)\.env(\.[A-Za-z0-9_-]+)?\.example$')
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | qg_quote
    qg_fail "a .env file is committed (only .env*.example templates may be)"
  else
    echo "Clean"
  fi
}

# qg_scan <name> <extended-regex> <pathspec>...: fails when a line this pull request adds matches.
qg_scan() {
  local name="$1" re="$2" out code
  shift 2
  qg_step "$name"
  out=$(bash "$QG_HERE/diff-scan.sh" "$QG_BASE" "$re" "$@")
  code=$?
  case $code in
  0) echo "Clean" ;;
  1)
    printf '%s\n' "$out" | qg_quote
    qg_fail "$name found a match in the lines this pull request adds"
    ;;
  *) qg_fail "$name could not read the diff against $QG_BASE" ;;
  esac
}

# The JavaScript scans every JS/TS stack runs over the lines a pull request adds.
qg_js_scans() {
  qg_scan "Dangerous JS APIs Check" '(^|[^[:alnum:]_$.])eval[[:space:]]*\(|new[[:space:]]+Function[[:space:]]*\(' "${QG_JS_CODE[@]}"
  qg_scan "Unsafe React Patterns Check" 'dangerouslySetInnerHTML|__html' "${QG_JS_CODE[@]}"
  qg_scan "URL Scheme Injection Check" '(javascript:|data:text/html|data:application/)' "${QG_JS_CODE[@]}"
}

# gitleaks over this pull request's commits only; earlier history was scanned by the pull requests
# that brought it. The repo's .gitleaks.toml allowlist applies when it exists.
qg_gitleaks() {
  qg_step "Secret Scan (gitleaks, this pull request's commits)"
  if ! command -v gitleaks >/dev/null 2>&1; then
    qg_skip "Secret Scan (gitleaks)" "gitleaks is not installed on this runner"
    return
  fi
  local args=(git . --no-banner --redact "--log-opts=${QG_BASE}..HEAD")
  [ -f .gitleaks.toml ] && args+=(--config .gitleaks.toml)
  if ! gitleaks "${args[@]}"; then
    qg_fail "gitleaks found a secret in this pull request's commits (or could not scan them)"
  fi
}

# SkillSpector, only when the pull request changed a skill, command, subagent or hook. The build
# installed is the commit scripts/check/skills.sh pins; skills.sh refuses any other.
qg_skill_scan() {
  qg_step "Skill Security Scan"
  if [ ! -f scripts/check/skills.sh ]; then
    echo "scripts/check/skills.sh is not installed; agent-core's setup adds it"
    return
  fi
  if git diff --quiet "${QG_BASE}...HEAD" -- "${QG_SKILL_PATHS[@]}"; then
    echo "No skill, command, subagent or hook changed - nothing to scan"
    return
  fi
  local ref
  ref=$(sed -n 's/^PINNED_REF="\([0-9a-f]\{40\}\)"$/\1/p' scripts/check/skills.sh)
  if ! command -v skillspector >/dev/null 2>&1 && command -v uv >/dev/null 2>&1 && [ -n "$ref" ]; then
    if uv tool install --quiet --python 3.12 "git+https://github.com/NVIDIA/skillspector.git@${ref}"; then
      PATH="$(uv tool dir --bin):$PATH"
    fi
  fi
  if ! command -v skillspector >/dev/null 2>&1; then
    qg_skip "Skill Security Scan" "SkillSpector could not be installed (uv and the pinned commit in scripts/check/skills.sh are needed)"
    return
  fi
  bash scripts/check/skills.sh --changed "$QG_BASE" || qg_fail "Skill Security Scan found a finding the baseline does not suppress"
}

# qg_build: the production build, which the pre-commit gates never run.
qg_build() {
  if qg_has_script build; then
    qg_run "Production Build" qg_pm_run build
  else
    qg_step "Production Build"
    qg_skip "Production Build" "package.json has no build script"
  fi
}

# qg_source_maps <dir>...: no source map ships in the client output.
qg_source_maps() {
  qg_step "Check Source Maps Leak"
  local maps
  maps=$(find "$@" -name '*.map' -type f 2>/dev/null | head -5)
  if [ -n "$maps" ]; then
    printf '%s\n' "$maps" | qg_quote
    qg_fail "source maps in the build output ($*)"
  else
    echo "Clean"
  fi
}

# The repo's own audit wrapper, when it ships one (agent-fe-nextjs and agent-docs-nextra install
# scripts/check/audit.ts, which reads `bun audit` correctly). Otherwise dependency-review.yml
# (agent-core) checks every dependency a pull request adds.
qg_js_audit() {
  qg_step "Security Audit"
  if [ -f scripts/check/audit.ts ] && [ "$QG_PM" = bun ]; then
    bun run scripts/check/audit.ts || qg_fail "Security Audit found a high or critical advisory (or could not read the report)"
  else
    echo "No scripts/check/audit.ts for $QG_PM; dependency-review.yml checks the dependencies this pull request adds"
  fi
}

# qg_repo_script <name> <script> [args...]: one of the repo's own check scripts, which the stack
# plugin's setup installs; a missing one is a check that did not run.
qg_repo_script() {
  local name="$1" script="$2"
  shift 2
  if [ -f "$script" ]; then
    qg_run "$name" bash "$script" "$@"
  else
    qg_step "$name"
    # shellcheck disable=SC2153 # gate.sh sets QG_STACK before it runs a stack's checks
    qg_skip "$name" "$script is missing: run /agent-${QG_STACK}:setup"
  fi
}

# qg_docker_build <name>: the repo's Dockerfile, when it has one, built without pulling newer bases.
qg_docker_build() {
  qg_step "$1"
  if [ ! -f Dockerfile ]; then
    echo "No Dockerfile; no image to build"
    return
  fi
  if ! command -v docker >/dev/null 2>&1; then
    qg_skip "$1" "the runner has no docker"
    return
  fi
  docker build --pull=false -t quality-gate-build . || qg_fail "docker build failed"
}

# ── PostgreSQL (be-go, be-axum) ──────────────────────────────────────────────────────────────
# The workflow's `database` input: false says the repo owns no schema, so no PostgreSQL starts and
# each database step says so instead of running.
qg_db_on() {
  [ "${QG_DATABASE:-true}" = true ]
}

qg_db_off_note() {
  echo "database is false: this repo owns no schema, so no PostgreSQL runs"
}

# qg_db_repo_script <name> <script> [args...]: qg_repo_script for a check about the repo's schema.
qg_db_repo_script() {
  if qg_db_on; then
    qg_repo_script "$@"
  else
    qg_step "$1"
    qg_db_off_note
  fi
}

# qg_db_url <name>: the superuser URL with another database name.
qg_db_url() {
  printf '%s' "$QG_PG_ADMIN_URL" | sed -E "s#^(postgres(ql)?://[^/?]*)(/[^?]*)?#\\1/$1#"
}

# The roles (and databases) the repo's tests connect with: db/roles.sql, once, as the superuser,
# before gates.list runs the tests. Without one, the tests connect as the env file says.
qg_db_roles() {
  qg_step "Database Roles (db/roles.sql)"
  if ! qg_db_on; then
    qg_db_off_note
    return
  fi
  if [ ! -f db/roles.sql ]; then
    echo "No db/roles.sql; the tests connect as the env file says"
    return
  fi
  if ! command -v psql >/dev/null 2>&1; then
    qg_skip "Database Roles" "psql is not installed on this runner"
    return
  fi
  psql "$QG_PG_ADMIN_URL" -X -q -v ON_ERROR_STOP=1 -f db/roles.sql ||
    qg_fail "db/roles.sql failed on an empty PostgreSQL"
}

# qg_db_migrate <name> <dir> <apply> <ready>: every migration in <dir>, applied from zero to the new
# empty database qg_migrations on a direct connection (a migrator holds a session-level advisory
# lock, so never through a pooler). <ready> prints why the migrator cannot run and fails, or
# succeeds silently; <apply> applies the migrations to $QG_MIGRATIONS_URL. QG_DB_STATE then says
# what the catalog checks can read: off, none (no migration yet), skipped, failed or ok.
qg_db_migrate() {
  local name="$1" dir="$2" apply="$3" ready="$4" why
  QG_DB_STATE=skipped
  qg_step "$name"
  if ! qg_db_on; then
    QG_DB_STATE=off
    qg_db_off_note
    return
  fi
  if [ -z "$(find "$dir" -maxdepth 1 -name '*.sql' 2>/dev/null | head -1)" ]; then
    QG_DB_STATE=none
    echo "No migration in $dir/ yet; nothing to apply"
    return
  fi
  if ! command -v psql >/dev/null 2>&1; then
    qg_skip "$name" "psql is not installed on this runner"
    return
  fi
  if ! why=$("$ready"); then
    qg_skip "$name" "$why"
    return
  fi
  if ! psql "$QG_PG_ADMIN_URL" -X -q -v ON_ERROR_STOP=1 -c 'set client_min_messages = warning' \
    -c 'drop database if exists qg_migrations' -c 'create database qg_migrations'; then
    QG_DB_STATE=failed
    qg_fail "$name could not create an empty database"
    return
  fi
  QG_MIGRATIONS_URL=$(qg_db_url qg_migrations)
  if "$apply"; then
    QG_DB_STATE=ok
  else
    QG_DB_STATE=failed
    qg_fail "$name: the migrations do not apply to an empty database"
  fi
}

# qg_db_no_rows <name> <sql file> <what a row means>: a catalog query on the migrated database that
# must return nothing. The rows name tables and indexes from the pull request, so they print quoted.
qg_db_no_rows() {
  local name="$1" rows
  qg_step "$name"
  case "${QG_DB_STATE:-skipped}" in
  off) qg_db_off_note && return ;;
  none) echo "No migration yet; nothing to check" && return ;;
  failed) echo "The migrations failed above; nothing to check" && return ;;
  skipped)
    qg_skip "$name" "the migrations did not run"
    return
    ;;
  esac
  if ! rows=$(psql "$QG_MIGRATIONS_URL" -X -q -A -t -F ' | ' -v ON_ERROR_STOP=1 -f "$QG_HERE/sql/$2"); then
    qg_fail "$name could not query the migrated database"
    return
  fi
  if [ -n "$rows" ]; then
    printf '%s\n' "$rows" | qg_quote
    qg_fail "$3"
  else
    echo "Clean"
  fi
}

qg_db_catalog() {
  qg_db_no_rows "Foreign Key Index Check" unindexed-fks.sql \
    "a foreign key has no index that leads with its columns (table | constraint | columns | references)"
  qg_db_no_rows "Invalid Index Check" invalid-indexes.sql \
    "an index is INVALID after the migrations (a failed CREATE INDEX CONCURRENTLY; schema | index | table)"
}

# The optional pooler check (input pgbouncer-tests): the repo's scripts/check/pooler.sh, run while
# PgBouncer 1.26.0 listens on 127.0.0.1:6432 in transaction mode. The repo's env file names the URL
# its tests use through it, TEST_POOLER_DATABASE_URL.
qg_pgbouncer_tests() {
  local name="PgBouncer Check (scripts/check/pooler.sh behind PgBouncer)"
  qg_step "$name"
  if [ "${QG_PGBOUNCER_TESTS:-false}" != true ]; then
    echo "pgbouncer-tests is off"
    return
  fi
  if ! qg_db_on; then
    qg_db_off_note
    return
  fi
  if [ ! -f scripts/check/pooler.sh ]; then
    qg_skip "PgBouncer Check" "scripts/check/pooler.sh is missing: run /agent-${QG_STACK}:setup"
    return
  fi
  if ! command -v docker >/dev/null 2>&1; then
    qg_skip "PgBouncer Check" "the runner has no docker to run PgBouncer in"
    return
  fi
  if [ -z "${TEST_POOLER_DATABASE_URL:-}" ]; then
    qg_fail "TEST_POOLER_DATABASE_URL is not set: add it to the env file (postgres://<role>@127.0.0.1:6432/<database>?sslmode=disable)"
    return
  fi
  bash "$QG_HERE/pgbouncer.sh" "$QG_TMP/pgbouncer" bash scripts/check/pooler.sh
  case $? in
  0) ;;
  3) qg_fail "PgBouncer did not start (the reason is above)" ;;
  *) qg_fail "scripts/check/pooler.sh failed behind PgBouncer" ;;
  esac
}

# qg_squawk <dir> [goose]: squawk over the migration files this pull request adds or changes, with
# the repo's .squawk.toml. A goose file keeps its down migration below `-- +goose Down`; that part
# never runs on deploy, so only the part above it is linted.
qg_squawk() {
  local dir="$1" flavor="${2:-}" name="Migration Lint (squawk)" files=() f rc bad=0
  qg_step "$name"
  if ! qg_db_on; then
    qg_db_off_note
    return
  fi
  while IFS= read -r f; do
    [ -f "$f" ] && files+=("$f")
  done < <(git diff --name-only --diff-filter=AM "${QG_BASE}...HEAD" -- "$dir/*.sql")
  if [ ${#files[@]} -eq 0 ]; then
    echo "No migration added or changed under $dir/"
    return
  fi
  if ! command -v squawk >/dev/null 2>&1; then
    qg_skip "$name" "squawk is not installed on this runner"
    return
  fi
  for f in "${files[@]}"; do
    if [ "$flavor" = goose ]; then
      awk 'tolower($0) ~ /^--[[:space:]]*\+goose[[:space:]]+down/ { exit } { print }' "$f" |
        squawk --stdin-filepath "$f" >"$QG_TMP/squawk.out" 2>&1
      rc=${PIPESTATUS[1]}
    else
      squawk "$f" >"$QG_TMP/squawk.out" 2>&1
      rc=$?
    fi
    qg_quote <"$QG_TMP/squawk.out"
    [ "$rc" -eq 0 ] || bad=1
  done
  [ "$bad" -eq 0 ] || qg_fail "squawk found an unsafe statement in a migration this pull request adds"
}

# The summary: failures, then what did not run. Returns the gate's exit code.
qg_summary() {
  printf '\n\033[1m── Summary\033[0m\n'
  if [ -n "$QG_SKIPPED" ]; then
    printf 'Checks that did NOT run:%s\n\n' "$QG_SKIPPED"
  fi
  if [ "$QG_FAILED" -gt 0 ]; then
    echo "::error::$QG_FAILED check(s) failed."
    return 1
  fi
  if [ -n "$QG_SKIPPED" ]; then
    if [ "${QG_STRICT:-true}" = "true" ]; then
      echo "::error::the gate was partial and strict is on: a check that did not run fails it."
      return 1
    fi
    echo "All checks that ran passed, but the gate was PARTIAL: see the list above."
    return 0
  fi
  echo "Full gate passed."
}
