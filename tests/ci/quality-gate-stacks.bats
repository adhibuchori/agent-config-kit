#!/usr/bin/env bats
# actions/quality-gate for the be-go, be-axum and ios-swiftui stacks: plan.sh's new inputs (phase,
# database, pgbouncer-tests, the pinned tools per stack), the env-file names the gate refuses, and
# gate.sh end to end on toy repositories with every toolchain stubbed: go, cargo, sqlx, psql, squawk,
# docker, swiftlint, xcodebuild and xcrun log their arguments, so the order and the exact commands
# are what the assertions read. Each failure case proves the gate says no.

load helpers

setup() {
  ci_isolate
  need_node
  REPO="$BATS_TEST_TMPDIR/repo"
  toy_repo "$REPO"
  stub_tools gitleaks uv
  cd "$REPO" || return 1
  rm package.json package-lock.json
  toy_commit "$REPO" "no node project"
}

gate() {
  QG_BASE="${QG_BASE:-dev}" run --separate-stderr bash "$QG/gate.sh"
}

plan() {
  run --separate-stderr bash "$QG/plan.sh"
}

# has_line <text>: plan's output holds exactly that line.
has_line() {
  grep -qxF "$1" <<<"$output"
}

# line_of <regex>: the first line of the stub log that matches, by number (0 when none does).
line_of() {
  local n
  n=$(grep -nE "$1" "$STUB_LOG" | head -1 | cut -d: -f1)
  echo "${n:-0}"
}

# A stub that logs its argv and runs the body given on stdin after that.
stub() { # $1 name
  {
    printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" "%s" "$*" >>"$STUB_LOG"\n' "$1"
    cat
  } >"$STUBS/$1"
  chmod +x "$STUBS/$1"
}

# psql answers the catalog queries with PSQL_FK_ROWS and PSQL_INVALID_ROWS, and lists two roles.
stub_db() {
  stub psql <<'EOF'
case "$*" in
*unindexed-fks.sql*) printf '%b' "${PSQL_FK_ROWS:-}" ;;
*invalid-indexes.sql*) printf '%b' "${PSQL_INVALID_ROWS:-}" ;;
*pg_roles*) printf 'app_rw\nagent_ro\n' ;;
esac
case "$*" in *roles.sql*) exit "${STUB_ROLES_EXIT:-0}" ;; esac
exit 0
EOF
  # squawk logs what it was handed on stdin, so the goose down section can be seen to be cut.
  stub squawk <<'EOF'
[ -t 0 ] || cat >>"$STUB_LOG"
exit "${STUB_SQUAWK_EXIT:-0}"
EOF
  stub docker <<'EOF'
case "$1 $2" in
"run --rm") echo "PgBouncer 1.26.0" ;;
"inspect -f") echo true ;;
esac
exit 0
EOF
  stub pg_isready <<'EOF'
exit 0
EOF
}

# ── plan.sh ─────────────────────────────────────────────────────────────────────────────────

@test "plan: phase splits only ios-swiftui; static, build and all set the tools, and every job gets gitleaks" {
  QG_STACK=ios-swiftui QG_BASE_REF=dev QG_PHASE=static plan
  [ "$status" -eq 0 ]
  # No SwiftLint on Linux: swiftlint-static aborts on a custom rule.
  has_line phase=static && has_line tools= && has_line gitleaks=true
  QG_STACK=ios-swiftui QG_BASE_REF=dev QG_PHASE=build plan
  # gates.list runs secrets.sh in the macOS job too, so gitleaks is installed there as well.
  has_line 'tools=swiftlint periphery' && has_line gitleaks=true
  QG_STACK=ios-swiftui QG_BASE_REF=dev plan
  has_line phase=all && has_line 'tools=swiftlint periphery' && has_line gitleaks=true
  QG_STACK=ios-swiftui QG_BASE_REF=dev QG_PHASE=deploy plan
  [ "$status" -eq 2 ] && [[ "$stderr" == *"phase must be static, build or all"* ]] || false
  QG_STACK=be-go QG_BASE_REF=dev QG_PHASE=static plan
  [ "$status" -eq 2 ] && [[ "$stderr" == *"phase splits only the ios-swiftui gate"* ]] || false
}

@test "plan: the macOS phase never installs uv for the skill scan; the static phase does" {
  printf 'PINNED_REF="%s"\n' "$(printf '0%.0s' {1..40})" >scripts/check/skills.sh
  toy_commit "$REPO" "skills.sh"
  git update-ref refs/remotes/origin/dev HEAD
  mkdir -p .claude/skills/tidy && printf -- '---\nname: tidy\n---\n' >.claude/skills/tidy/SKILL.md
  toy_commit "$REPO" skill
  QG_STACK=ios-swiftui QG_BASE_REF=dev QG_PHASE=static plan
  has_line uv=true
  QG_STACK=ios-swiftui QG_BASE_REF=dev QG_PHASE=build plan
  has_line uv=false
}

@test "plan: be-go sets up Go and golangci-lint, plus squawk when it owns a schema" {
  QG_STACK=be-go QG_BASE_REF=dev plan
  [ "$status" -eq 0 ]
  has_line go=true && has_line rust=false && has_line pm=none
  has_line 'tools=golangci-lint squawk'
  QG_STACK=be-go QG_BASE_REF=dev QG_DATABASE=false plan
  has_line tools=golangci-lint
  QG_STACK=be-go QG_BASE_REF=dev QG_PACKAGE_MANAGER=bun plan
  [ "$status" -eq 2 ] && [[ "$stderr" == *"be-go installs no JavaScript dependencies"* ]] || false
}

@test "plan: be-axum sets up Rust and the cargo tools, plus squawk and sqlx-cli with a schema" {
  QG_STACK=be-axum QG_BASE_REF=dev plan
  [ "$status" -eq 0 ]
  has_line rust=true && has_line go=false
  has_line 'tools=cargo-llvm-cov cargo-nextest cargo-deny squawk sqlx-cli'
  QG_STACK=be-axum QG_BASE_REF=dev QG_DATABASE=false plan
  has_line 'tools=cargo-llvm-cov cargo-nextest cargo-deny'
}

@test "plan: pgbouncer-tests is a boolean for be-go and be-axum with a database; its max is a whole number" {
  QG_STACK=be-go QG_BASE_REF=dev QG_PGBOUNCER_TESTS=true QG_PGBOUNCER_MAX_PREPARED=0 plan
  [ "$status" -eq 0 ]
  QG_STACK=be-axum QG_BASE_REF=dev QG_PGBOUNCER_TESTS=true plan
  [ "$status" -eq 0 ]
  QG_STACK=be-hono QG_BASE_REF=dev QG_PGBOUNCER_TESTS=true plan
  [ "$status" -eq 2 ] && [[ "$stderr" == *"pgbouncer-tests is for be-go and be-axum"* ]] || false
  QG_STACK=be-go QG_BASE_REF=dev QG_PGBOUNCER_TESTS=true QG_DATABASE=false plan
  [ "$status" -eq 2 ] && [[ "$stderr" == *"pgbouncer-tests needs database: true"* ]] || false
  QG_STACK=be-go QG_BASE_REF=dev QG_PGBOUNCER_TESTS=yes plan
  [ "$status" -eq 2 ]
  QG_STACK=be-go QG_BASE_REF=dev QG_PGBOUNCER_MAX_PREPARED=-1 plan
  [ "$status" -eq 2 ] && [[ "$stderr" == *"pgbouncer-max-prepared-statements must be a whole number"* ]] || false
  QG_STACK=be-go QG_BASE_REF=dev QG_PGBOUNCER_MAX_PREPARED=1.5 plan
  [ "$status" -eq 2 ]
  QG_STACK=be-go QG_BASE_REF=dev QG_DATABASE=maybe plan
  [ "$status" -eq 2 ] && [[ "$stderr" == *"database must be true or false"* ]] || false
}

@test "gate: a phase other than all on a stack that is not split exits 2 before any check" {
  QG_STACK=be-go QG_PHASE=build gate
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"QG_PHASE must be all"* ]] || false
  [ ! -s "$STUB_LOG" ]
}

# ── the names an env file may not set ───────────────────────────────────────────────────────

@test "env file: toolchain variables of Go, Rust, sqlx and Xcode are refused; GOOGLE_* is not" {
  printf 'process.exit(0)\n' >scripts/check/site-audit.mjs
  printf '{"name":"toy","scripts":{"build":"next build"}}\n' >package.json
  printf '{"lockfileVersion": 3}\n' >package-lock.json
  toy_commit "$REPO" site
  stub_tools gitleaks uv npm
  local key
  for key in GOFLAGS GOTOOLCHAIN GOPROXY GO111MODULE GO_EXTLINK_ENABLED GOROOT_FINAL CGO_ENABLED \
    CARGO_HOME CARGO_BUILD_RUSTFLAGS RUSTUP_TOOLCHAIN RUSTC_WRAPPER RUSTFLAGS RUSTDOCFLAGS SQLX_OFFLINE DEVELOPER_DIR; do
    printf '%s=x\n' "$key" >.env.ci.example
    QG_STACK=fe-nextjs-static gate
    [ "$status" -eq 1 ] || { echo "not refused: $key" >&2; return 1; }
    [[ "$output" == *"$key changes how the runner or a toolchain behaves"* ]] || false
  done
  printf 'GOOGLE_CLIENT_ID=dummy\nGOLD_PRICE=1\nCARGO=freight\n' >.env.ci.example
  QG_STACK=fe-nextjs-static gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"loaded 3 variable(s)"* ]] || false
}

@test "env file: the gate and the stacks' ci-env.sh refuse the very same names" {
  local ci_env="$KIT_ROOT/plugins/agent-be-hono/templates/be-hono/scripts/check/ci-env.sh" gate_re env_re
  gate_re=$(sed -n "s/^QG_REFUSED_ENV='\(.*\)'$/\1/p" "$QG/lib.sh")
  env_re=$(sed -n 's/^REFUSED = re.compile(r"\(.*\)")$/\1/p' "$ci_env")
  [ -n "$gate_re" ]
  [ "$gate_re" = "$env_re" ]
}

# ── be-go ───────────────────────────────────────────────────────────────────────────────────

# be_go_repo: a Go service with the settings agent-be-go's rules ask for, one migration in the base
# branch and one the pull request adds, and the repo's own migrations.sh.
be_go_repo() {
  printf 'module example.com/svc\n\ngo 1.27\n' >go.mod
  mkdir -p cmd/api internal/httpapi internal/postgres db/migrations
  printf -- '-- +goose Up\ncreate table owners (id bigint primary key);\n' >db/migrations/00001_owners.sql
  toy_commit "$REPO" "base migration"
  git update-ref refs/remotes/origin/dev HEAD
  cat >cmd/api/main.go <<'EOF'
package main

// The four server timeouts.
var srv = &http.Server{ReadHeaderTimeout: 5, ReadTimeout: 10, WriteTimeout: 10, IdleTimeout: 60}
EOF
  printf 'package httpapi\n\nfunc limit(w http.ResponseWriter, r *http.Request) { r.Body = http.MaxBytesReader(w, r.Body, 1<<20) }\n' \
    >internal/httpapi/limit.go
  cat >internal/postgres/pool.go <<'EOF'
package postgres

func configure(cfg *pgxpool.Config) {
	cfg.MaxConns = 10
	cfg.MaxConnLifetime = time.Hour
	cfg.ConnConfig.ConnectTimeout = 5 * time.Second
}
EOF
  printf -- '-- +goose Up\ncreate table pets (id bigint primary key);\n-- +goose Down\ndrop table pets;\n' \
    >db/migrations/00002_pets.sql
  printf '#!/usr/bin/env bash\necho "migrations.sh $*" >>"$STUB_LOG"\nexit "${MIGRATIONS_EXIT:-0}"\n' >scripts/check/migrations.sh
  printf 'TEST_DATABASE_URL=postgres://app_rw@127.0.0.1:5432/app_test?sslmode=disable\n' >.env.ci.example
  toy_commit "$REPO" "be-go layout"
  stub go <<'EOF'
[ "$1 $2" = "mod download" ] && echo "go env GOTOOLCHAIN=$GOTOOLCHAIN GOFLAGS=$GOFLAGS" >>"$STUB_LOG"
case "$*" in
"tool -n goose") exit "${STUB_GOOSE_READY_EXIT:-0}" ;;
"tool goose "*) exit "${STUB_GOOSE_EXIT:-0}" ;;
"tool -n govulncheck") exit "${STUB_VULN_READY_EXIT:-0}" ;;
"tool govulncheck "*) exit "${STUB_VULN_EXIT:-0}" ;;
esac
exit 0
EOF
  stub_db
}

@test "gate: be-go runs the database checks in order on a fresh database, then the PR checks" {
  be_go_repo
  QG_STACK=be-go QG_COVERAGE_THRESHOLD=0 gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"Full gate passed."* ]] || false
  grep -qx 'go env GOTOOLCHAIN=local GOFLAGS=-mod=readonly' "$STUB_LOG"
  local download roles fresh goose fk invalid base squawk vuln build
  download=$(line_of '^go mod download$')
  [ "$(line_of '^go mod verify$')" -gt "$download" ]
  roles=$(line_of '^psql .* -f db/roles.sql$')
  [ "$roles" -eq 0 ] # no db/roles.sql in this repo
  fresh=$(line_of '^psql .*drop database if exists qg_migrations.*create database qg_migrations')
  goose=$(line_of '^go tool goose -dir db/migrations postgres postgresql://postgres@127.0.0.1:5432/qg_migrations\?sslmode=disable up$')
  fk=$(line_of '^psql postgresql://postgres@127.0.0.1:5432/qg_migrations.*unindexed-fks.sql')
  invalid=$(line_of 'invalid-indexes.sql')
  base=$(line_of '^migrations.sh --base origin/dev$')
  squawk=$(line_of '^squawk --stdin-filepath db/migrations/00002_pets.sql$')
  vuln=$(line_of '^go tool govulncheck ./...$')
  build=$(line_of '^go build -trimpath ./...$')
  [ "$download" -gt 0 ] && [ "$fresh" -gt "$download" ] && [ "$goose" -gt "$fresh" ]
  [ "$fk" -gt "$goose" ] && [ "$invalid" -gt "$fk" ] && [ "$base" -gt "$invalid" ]
  [ "$squawk" -gt "$base" ] && [ "$vuln" -gt "$squawk" ] && [ "$build" -gt "$vuln" ]
  # squawk lints only the migration the pull request adds, without its down section.
  run ! grep -q '00001_owners' "$STUB_LOG"
  grep -q 'create table pets' "$STUB_LOG"
  run ! grep -q 'drop table pets' "$STUB_LOG"
  # PgBouncer is off: docker never runs.
  run ! grep -q '^docker ' "$STUB_LOG"
  grep -q '^gitleaks git . --no-banner --redact --log-opts=origin/dev..HEAD$' "$STUB_LOG"
}

@test "gate: be-go runs db/roles.sql before the tests, and a failing one fails the gate" {
  be_go_repo
  printf 'create role app_rw login;\n' >db/roles.sql
  toy_commit "$REPO" roles
  QG_STACK=be-go QG_COVERAGE_THRESHOLD=0 gate
  [ "$status" -eq 0 ]
  [ "$(line_of '^psql postgresql://postgres@127.0.0.1:5432/postgres\?sslmode=disable -X -q -v ON_ERROR_STOP=1 -f db/roles.sql$')" -gt 0 ]
  [[ "$output" == *"Database Roles (db/roles.sql)"*"gates.sh ran"* ]] || false
  STUB_ROLES_EXIT=3 QG_STACK=be-go QG_COVERAGE_THRESHOLD=0 gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"db/roles.sql failed on an empty PostgreSQL"* ]] || false
}

@test "gate: be-go fails an unindexed foreign key and an INVALID index, and prints the rows" {
  be_go_repo
  PSQL_FK_ROWS='pets | pets_owner_id_fkey | owner_id | owners\n' PSQL_INVALID_ROWS='public | pets_name_idx | pets\n' \
    QG_STACK=be-go QG_COVERAGE_THRESHOLD=0 gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"pets | pets_owner_id_fkey | owner_id | owners"* ]] || false
  [[ "$output" == *"a foreign key has no index that leads with its columns"* ]] || false
  [[ "$output" == *"public | pets_name_idx | pets"* ]] || false
  [[ "$output" == *"an index is INVALID after the migrations"* ]] || false
}

@test "gate: be-go fails a migration that does not apply; the catalog checks then read nothing" {
  be_go_repo
  STUB_GOOSE_EXIT=1 QG_STACK=be-go QG_COVERAGE_THRESHOLD=0 gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"the migrations do not apply to an empty database"* ]] || false
  [[ "$output" == *"The migrations failed above; nothing to check"* ]] || false
  run ! grep -q 'unindexed-fks.sql' "$STUB_LOG"
}

@test "gate: be-go without goose in go.mod did not run its migrations, which fails a strict gate" {
  be_go_repo
  STUB_GOOSE_READY_EXIT=2 QG_STACK=be-go QG_COVERAGE_THRESHOLD=0 gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"Migrations From Zero (goose up) did not run: go.mod has no tool line for goose"* ]] || false
  [[ "$output" == *"Foreign Key Index Check did not run: the migrations did not run"* ]] || false
  run ! grep -q 'create database qg_migrations' "$STUB_LOG"
}

@test "gate: be-go with database false starts nothing that needs PostgreSQL" {
  be_go_repo
  QG_DATABASE=false QG_STACK=be-go QG_COVERAGE_THRESHOLD=0 gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"database is false: this repo owns no schema"* ]] || false
  run ! grep -qE '^(psql|squawk|docker|migrations.sh|go tool goose)' "$STUB_LOG"
}

@test "gate: be-go fails a squawk finding, a reachable vulnerability and a weak server or pool" {
  be_go_repo
  sed -e 's/, IdleTimeout: 60//' cmd/api/main.go >cmd/api/new && mv cmd/api/new cmd/api/main.go
  sed -e 's/MaxConns = 10/MaxConns = 1/' internal/postgres/pool.go >internal/postgres/new && mv internal/postgres/new internal/postgres/pool.go
  toy_commit "$REPO" weaker
  STUB_SQUAWK_EXIT=1 STUB_VULN_EXIT=3 QG_STACK=be-go QG_COVERAGE_THRESHOLD=0 gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"squawk found an unsafe statement"* ]] || false
  [[ "$output" == *"govulncheck found a vulnerability the code reaches"* ]] || false
  [[ "$output" == *"the http.Server never sets IdleTimeout"* ]] || false
  [[ "$output" == *"a pool of 1 or 2 connections"* ]] || false
  [[ "$output" != *"never sets ReadTimeout"* ]] || false
}

@test "gate: be-go without govulncheck in go.mod or migrations.sh records checks that did not run" {
  be_go_repo
  rm scripts/check/migrations.sh
  toy_commit "$REPO" "no migrations.sh"
  STUB_VULN_READY_EXIT=2 QG_STRICT=false QG_STACK=be-go QG_COVERAGE_THRESHOLD=0 gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"PARTIAL"* ]] || false
  [[ "$output" == *"Vulnerability Scan: go.mod has no tool line for govulncheck"* ]] || false
  [[ "$output" == *"Migrations Against the Base Branch: scripts/check/migrations.sh is missing: run /agent-be-go:setup"* ]] || false
}

@test "gate: be-go reads Go's coverage profile for the floor" {
  be_go_repo
  TOY_LCOV='' QG_STACK=be-go QG_COVERAGE_THRESHOLD=100 gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"Coverage Floor did not run"*"coverage.out"* ]] || false
  mkdir -p coverage
  printf 'mode: atomic\nexample.com/svc/a.go:1.1,2.2 3 1\nexample.com/svc/a.go:3.1,4.2 1 0\n' >coverage/coverage.out
  QG_STACK=be-go QG_COVERAGE_THRESHOLD=100 gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"statements"*"3 / 4"*"BELOW"* ]] || false
  QG_STACK=be-go QG_COVERAGE_THRESHOLD=75 gate
  [ "$status" -eq 0 ]
}

# ── the PgBouncer check (be-go here; be-axum calls the same function) ─────────────────────────

pooler_repo() {
  be_go_repo
  printf '#!/usr/bin/env bash\necho "pooler.sh TEST_POOLER_DATABASE_URL=$TEST_POOLER_DATABASE_URL" >>"$STUB_LOG"\nexit "${POOLER_EXIT:-0}"\n' \
    >scripts/check/pooler.sh
  printf 'TEST_POOLER_DATABASE_URL=postgres://app_rw@127.0.0.1:6432/app_test?sslmode=disable\n' >>.env.ci.example
  toy_commit "$REPO" pooler
}

@test "gate: pgbouncer-tests runs pooler.sh behind PgBouncer after the migrations" {
  pooler_repo
  QG_PGBOUNCER_TESTS=true QG_PGBOUNCER_MAX_PREPARED=0 QG_STACK=be-go QG_COVERAGE_THRESHOLD=0 gate
  [ "$status" -eq 0 ]
  local goose start pooler removed base
  goose=$(line_of '^go tool goose ')
  start=$(line_of '^docker run -d ')
  pooler=$(line_of '^pooler.sh TEST_POOLER_DATABASE_URL=postgres://app_rw@127.0.0.1:6432/app_test\?sslmode=disable$')
  removed=$(line_of '^docker rm -f qg-pgbouncer-')
  base=$(line_of '^migrations.sh --base')
  [ "$goose" -gt 0 ] && [ "$start" -gt "$goose" ] && [ "$pooler" -gt "$start" ]
  [ "$removed" -gt "$pooler" ] && [ "$base" -gt "$removed" ]
  [[ "$output" == *"max_prepared_statements 0"* ]] || false
}

@test "gate: a failing pooler.sh fails the gate; a missing one or no docker did not run" {
  pooler_repo
  POOLER_EXIT=1 QG_PGBOUNCER_TESTS=true QG_STACK=be-go QG_COVERAGE_THRESHOLD=0 gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"scripts/check/pooler.sh failed behind PgBouncer"* ]] || false
  rm "$STUBS/docker"
  PATH="$(path_without docker)" QG_PGBOUNCER_TESTS=true QG_STACK=be-go QG_COVERAGE_THRESHOLD=0 gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"PgBouncer Check did not run: the runner has no docker"* ]] || false
  rm scripts/check/pooler.sh
  toy_commit "$REPO" "no pooler.sh"
  QG_PGBOUNCER_TESTS=true QG_STACK=be-go QG_COVERAGE_THRESHOLD=0 gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"PgBouncer Check did not run: scripts/check/pooler.sh is missing"* ]] || false
}

@test "gate: pgbouncer-tests without TEST_POOLER_DATABASE_URL in the env file fails" {
  pooler_repo
  printf 'TEST_DATABASE_URL=postgres://app_rw@127.0.0.1:5432/app_test\n' >.env.ci.example
  toy_commit "$REPO" "no pooler url"
  QG_PGBOUNCER_TESTS=true QG_STACK=be-go QG_COVERAGE_THRESHOLD=0 gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"TEST_POOLER_DATABASE_URL is not set"* ]] || false
  run ! grep -q '^pooler.sh' "$STUB_LOG"
}

# ── be-axum ─────────────────────────────────────────────────────────────────────────────────

be_axum_repo() {
  printf '[toolchain]\nchannel = "1.99.0"\n' >rust-toolchain.toml
  printf '# lock\n' >Cargo.lock
  printf '[advisories]\n' >deny.toml
  mkdir -p src/platform src/bin migrations
  printf 'create table owners (id bigint primary key);\n' >migrations/20260101000000_owners.sql
  cat >src/platform/db.rs <<'EOF'
pub fn options() -> PgPoolOptions {
    PgPoolOptions::new().max_connections(10).acquire_timeout(Duration::from_secs(3)).max_lifetime(Duration::from_secs(1800))
}
pub fn connect() -> PgConnectOptions { url.parse()?.extra_float_digits(None) }
EOF
  printf 'fn main() {}\n' >src/bin/openapi.rs
  printf '{"openapi":"3.1.0"}\n' >openapi.json
  printf '#!/usr/bin/env bash\necho "migrations.sh $*" >>"$STUB_LOG"\n' >scripts/check/migrations.sh
  printf 'DATABASE_URL=postgres://app_rw@127.0.0.1:5432/app_test\n' >.env.ci.example
  toy_commit "$REPO" "be-axum layout"
  stub cargo <<'EOF'
[ "$1" = fetch ] && echo "cargo env RUSTUP_AUTO_INSTALL=$RUSTUP_AUTO_INSTALL" >>"$STUB_LOG"
case "$*" in
"sqlx prepare "*) echo "cargo sqlx DATABASE_URL=$DATABASE_URL" >>"$STUB_LOG"; exit "${STUB_PREPARE_EXIT:-0}" ;;
"run --locked --quiet --bin openapi") [ -n "${SPEC_DRIFT:-}" ] && echo '{"openapi":"3.1.1"}' >openapi.json ;;
"deny "*) exit "${STUB_DENY_EXIT:-0}" ;;
esac
exit 0
EOF
  stub sqlx <<'EOF'
echo "sqlx DATABASE_URL=$DATABASE_URL" >>"$STUB_LOG"
exit "${STUB_SQLX_EXIT:-0}"
EOF
  stub cargo-deny <<'EOF'
exit 0
EOF
  stub_db
}

@test "gate: be-axum migrates a fresh database with sqlx, checks the query cache, then the PR checks" {
  be_axum_repo
  QG_STACK=be-axum QG_COVERAGE_THRESHOLD=0 gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"Full gate passed."* ]] || false
  grep -qx 'cargo env RUSTUP_AUTO_INSTALL=0' "$STUB_LOG"
  local fetch migrate prepare fk base squawk deny spec build url
  url='postgresql://postgres@127.0.0.1:5432/qg_migrations?sslmode=disable'
  fetch=$(line_of '^cargo fetch --locked$')
  migrate=$(line_of '^sqlx migrate run --no-dotenv --source migrations$')
  grep -qxF "sqlx DATABASE_URL=$url" "$STUB_LOG"
  prepare=$(line_of '^cargo sqlx prepare --check --no-dotenv -- --all-targets$')
  grep -qxF "cargo sqlx DATABASE_URL=$url" "$STUB_LOG"
  fk=$(line_of 'unindexed-fks.sql')
  base=$(line_of '^migrations.sh --base origin/dev$')
  squawk=$(line_of '^squawk migrations/20260101000000_owners.sql$')
  deny=$(line_of '^cargo deny --locked check$')
  spec=$(line_of '^cargo run --locked --quiet --bin openapi$')
  build=$(line_of '^cargo build --locked --release$')
  [ "$fetch" -gt 0 ] && [ "$migrate" -gt "$fetch" ] && [ "$prepare" -gt "$migrate" ] && [ "$fk" -gt "$prepare" ]
  [ "$base" -gt "$fk" ] && [ "$squawk" -gt "$base" ] && [ "$deny" -gt "$squawk" ]
  [ "$spec" -gt "$deny" ] && [ "$build" -gt "$spec" ]
}

@test "gate: be-axum fails a stale query cache, a stale spec, a deny finding and a pool without its settings" {
  be_axum_repo
  sed -e 's/.extra_float_digits(None)//' src/platform/db.rs >src/platform/new && mv src/platform/new src/platform/db.rs
  toy_commit "$REPO" "no float digits"
  STUB_PREPARE_EXIT=1 SPEC_DRIFT=1 STUB_DENY_EXIT=1 QG_STACK=be-axum QG_COVERAGE_THRESHOLD=0 gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"the .sqlx query cache is stale"* ]] || false
  [[ "$output" == *"openapi.json is stale or uncommitted"* ]] || false
  [[ "$output" == *"cargo deny found"* ]] || false
  [[ "$output" == *"the pool never calls extra_float_digits"* ]] || false
}

@test "gate: be-axum needs rust-toolchain.toml and a committed Cargo.lock before anything runs" {
  be_axum_repo
  git rm -q Cargo.lock
  toy_commit "$REPO" "no lock"
  QG_STACK=be-axum QG_COVERAGE_THRESHOLD=0 gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"Cargo.lock is not committed"* ]] || false
  run ! grep -q '^cargo fetch' "$STUB_LOG"
  printf '# lock\n' >Cargo.lock
  git rm -q rust-toolchain.toml
  toy_commit "$REPO" "no toolchain file"
  QG_STACK=be-axum QG_COVERAGE_THRESHOLD=0 gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"no rust-toolchain.toml"* ]] || false
}

@test "gate: be-axum without sqlx-cli did not run its migrations or the query cache check" {
  be_axum_repo
  rm "$STUBS/sqlx"
  PATH="$(path_without sqlx)" QG_STRICT=false QG_STACK=be-axum QG_COVERAGE_THRESHOLD=0 gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"Migrations From Zero (sqlx migrate run): sqlx-cli is not installed on this runner"* ]] || false
  [[ "$output" == *"Query Cache Check (cargo sqlx prepare --check): the migrations did not run"* ]] || false
}

# ── ios-swiftui ─────────────────────────────────────────────────────────────────────────────

# ios_repo: a gates.list mixing Linux-safe and macOS-only lines, the scripts those lines run, and a
# toy Xcode project.
ios_repo() {
  cat >scripts/check/gates.list <<'EOF'
# the iOS gates
all	xcrun swift-format lint --strict --recursive App Packages UITests
all	bash scripts/check/secrets.sh
code	swiftlint lint --quiet
code	bash scripts/check/xcode-settings.sh
code	node scripts/check/folder-shape.mjs
code	swiftlint lintx
code	bash scripts/check/ai-config.sh --verbose
code	bash scripts/check/ci-env.sh bash scripts/check/coverage.sh
EOF
  printf '#!/usr/bin/env bash\necho "secrets.sh ran" >>"$STUB_LOG"\nexit "${STUB_SECRETS_EXIT:-0}"\n' >scripts/check/secrets.sh
  printf '#!/usr/bin/env bash\necho "ai-config.sh $*" >>"$STUB_LOG"\n' >scripts/check/ai-config.sh
  printf '#!/usr/bin/env bash\nplutil -convert json -o - App.xcodeproj/project.pbxproj\n' >scripts/check/xcode-settings.sh
  printf 'import { appendFileSync } from "node:fs";\nappendFileSync(process.env.STUB_LOG, "folder-shape ran\\n");\n' \
    >scripts/check/folder-shape.mjs
  printf 'import { appendFileSync } from "node:fs";\nappendFileSync(process.env.STUB_LOG, `i18n-catalog ${process.argv.slice(2).join(" ")}\\n`);\n' \
    >scripts/check/i18n-catalog.mjs
  mkdir -p App.xcodeproj
  printf 'project_file_location: App.xcodeproj\n' >.periphery.yml
  toy_commit "$REPO" "ios layout"
  stub swiftlint <<'EOF'
exit "${STUB_SWIFTLINT_EXIT:-0}"
EOF
  stub_tools gitleaks uv plutil swift periphery
  stub xcodebuild <<'EOF'
[ "$1" = -version ] && printf '%s\nBuild version 27A266a\n' "${XCODE_LINE:-Xcode 27.0}"
exit "${STUB_XCODEBUILD_EXIT:-0}"
EOF
  stub xcrun <<'EOF'
case "$*" in
"simctl list devices available -j")
  echo '{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-2":[{"udid":"OLD-UDID","name":"iPhone 17","isAvailable":true}],
   "com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"udid":"IPAD-UDID","name":"iPad Pro","isAvailable":true},{"udid":"NEW-UDID","name":"iPhone 18 Pro","isAvailable":true}],
   "com.apple.CoreSimulator.SimRuntime.watchOS-27-0":[{"udid":"WATCH","name":"Apple Watch","isAvailable":true}]}}' ;;
"simctl bootstatus "*)
  exit "${STUB_BOOT_EXIT:-0}" ;;
"xcresulttool get build-results "*)
  printf '{"warningCount":%s,"warnings":[{"issueType":"Swift Compiler Warning","message":"var never mutated","sourceURL":"App/Screens/Home.swift"}]}\n' "${XCODE_WARNINGS:-0}" ;;
esac
exit 0
EOF
}

@test "gate: the iOS static phase runs only the Linux-safe gates.list lines, as written" {
  ios_repo
  QG_STACK=ios-swiftui QG_PHASE=static gate
  [ "$status" -eq 0 ]
  grep -qx 'folder-shape ran' "$STUB_LOG"
  grep -qx 'secrets.sh ran' "$STUB_LOG"
  grep -qx 'ai-config.sh --verbose' "$STUB_LOG"
  [[ "$output" == *"3 gates.list line(s) ran here"* ]] || false
  # SwiftLint waits for the macOS job: swiftlint-static aborts on a custom rule.
  [[ "$output" == *"  swiftlint lint --quiet"* ]] || false
  [[ "$output" == *"  xcrun swift-format lint --strict --recursive App Packages UITests"* ]] || false
  [[ "$output" == *"  bash scripts/check/xcode-settings.sh"* ]] || false
  [[ "$output" == *"  swiftlint lintx"* ]] || false
  [[ "$output" == *"  bash scripts/check/ci-env.sh bash scripts/check/coverage.sh"* ]] || false
  # The pull-request checks run here, and only here.
  [[ "$output" == *"Check .env Not Committed"* ]] || false
  grep -q '^gitleaks git . --no-banner --redact --log-opts=origin/dev..HEAD$' "$STUB_LOG"
  # Nothing that needs a Mac ran, and a line that only looks like an allowed one did not either.
  run ! grep -qE '^(xcrun|plutil|swift|xcodebuild|periphery) ' "$STUB_LOG"
  run ! grep -q 'lintx' "$STUB_LOG"
  run ! grep -q '^swiftlint ' "$STUB_LOG"
}

@test "gate: a failing Linux-safe line fails the static phase" {
  ios_repo
  STUB_SECRETS_EXIT=2 QG_STACK=ios-swiftui QG_PHASE=static gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"bash scripts/check/secrets.sh failed"* ]] || false
}

@test "gate: the iOS build phase runs the whole list, builds on the newest iPhone, and never rescans the PR" {
  ios_repo
  QG_STACK=ios-swiftui QG_PHASE=build QG_XCODE_VERSION=27.0 QG_COVERAGE_THRESHOLD=0 gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"gates.sh ran"* ]] || false
  local test_line
  test_line=$(grep '^xcodebuild test ' "$STUB_LOG")
  [[ "$test_line" == "xcodebuild test -project App.xcodeproj -scheme App -destination id=NEW-UDID -derivedDataPath "*"/ios/DerivedData -resultBundlePath "*"/ios/test.xcresult -onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=YES" ]] || false
  [[ "$test_line" != *"retry"* ]] || false
  # The simulator is booted and waited for before the build, never left to xcodebuild.
  grep -qx 'xcrun simctl bootstatus NEW-UDID -b' "$STUB_LOG"
  [ "$(line_of '^xcrun simctl bootstatus ')" -lt "$(line_of '^xcodebuild test ')" ]
  grep -q '^xcrun xcresulttool get build-results --path .*/ios/test.xcresult --compact$' "$STUB_LOG"
  grep -q '^i18n-catalog --stringsdata .*/ios/DerivedData$' "$STUB_LOG"
  grep -q '^periphery scan --strict --disable-update-check --index-store-path .*/ios/DerivedData/Index.noindex/DataStore$' "$STUB_LOG"
  [[ "$output" == *"0 build warning(s)"* ]] || false
  run ! grep -q '^gitleaks ' "$STUB_LOG"
  run ! grep -q '^swiftlint ' "$STUB_LOG" # it runs through gates.sh, which the toy replaces
}

@test "gate: the iOS build fails on one build warning, and a named scheme is used" {
  ios_repo
  XCODE_WARNINGS=1 QG_IOS_SCHEME=AppCI QG_STACK=ios-swiftui QG_PHASE=build QG_COVERAGE_THRESHOLD=0 gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"App/Screens/Home.swift: var never mutated"* ]] || false
  [[ "$output" == *"the build has warnings; the gate allows none"* ]] || false
  grep -q '^xcodebuild test -project App.xcodeproj -scheme AppCI ' "$STUB_LOG"
}

@test "gate: another Xcode stops the build phase before any gate runs" {
  ios_repo
  XCODE_LINE="Xcode 26.6" QG_STACK=ios-swiftui QG_PHASE=build QG_XCODE_VERSION=27.0 gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"the runner's Xcode is 'Xcode 26.6', not the pinned Xcode 27.0"* ]] || false
  [[ "$output" != *"gates.sh ran"* ]] || false
  run ! grep -q '^xcodebuild test' "$STUB_LOG"
}

@test "gate: a failed xcodebuild test fails the gate, and the checks that need the build did not run" {
  ios_repo
  STUB_XCODEBUILD_EXIT=65 QG_STRICT=false QG_STACK=ios-swiftui QG_PHASE=build QG_COVERAGE_THRESHOLD=0 gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"xcodebuild test failed (scheme App, simulator NEW-UDID)"* ]] || false
  [[ "$output" == *"String Catalog Check, built (I3, I4): the build did not finish"* ]] || false
  run ! grep -q '^periphery ' "$STUB_LOG"
}

@test "gate: a simulator that does not finish booting fails the gate before the build" {
  ios_repo
  STUB_BOOT_EXIT=1 QG_STRICT=false QG_STACK=ios-swiftui QG_PHASE=build QG_COVERAGE_THRESHOLD=0 gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"the simulator NEW-UDID did not finish booting"* ]] || false
  run ! grep -q '^xcodebuild test' "$STUB_LOG"
}

@test "gate: the iOS client drift check regenerates the client and fails on a diff" {
  ios_repo
  mkdir -p Packages/AppCore/Sources/APIClient
  printf 'generate: [types, client]\n' >Packages/AppCore/Sources/APIClient/openapi-generator-config.yaml
  printf 'struct Client {}\n' >Packages/AppCore/Sources/APIClient/Client.swift
  toy_commit "$REPO" client
  QG_STACK=ios-swiftui QG_PHASE=build QG_COVERAGE_THRESHOLD=0 gate
  [ "$status" -eq 0 ]
  grep -qx 'swift package --package-path Packages/AppCore --force-resolved-versions --allow-writing-to-package-directory generate-code-from-openapi --target APIClient' "$STUB_LOG"
  stub swift <<'EOF'
echo 'struct Client { let changed = true }' >Packages/AppCore/Sources/APIClient/Client.swift
EOF
  QG_STACK=ios-swiftui QG_PHASE=build QG_COVERAGE_THRESHOLD=0 gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"the committed API client differs from what openapi.json generates"* ]] || false
}

@test "gate: the iOS all phase runs the static checks, then the build" {
  ios_repo
  QG_STACK=ios-swiftui QG_COVERAGE_THRESHOLD=0 gate
  [ "$status" -eq 0 ]
  [ "$(line_of '^gitleaks ')" -gt 0 ]
  [ "$(line_of '^xcodebuild test ')" -gt "$(line_of '^gitleaks ')" ]
}

@test "gate: every IOS_LINUX_GATES entry is a line of the ios-swiftui template's gates.list" {
  local list="$KIT_ROOT/plugins/agent-ios-swiftui/templates/ios-swiftui/scripts/check/gates.list" e
  [ -f "$list" ] || skip "the ios-swiftui template is not in this tree yet"
  # shellcheck source=/dev/null
  . "$QG/stacks/ios-swiftui.sh"
  for e in "${IOS_LINUX_GATES[@]}"; do
    cut -f2 "$list" | grep -qE "^${e}( |$)" || { echo "not in gates.list: $e" >&2; return 1; }
    case "$e" in bash\ * | node\ *)
      local script="${e#* }" path
      path="$KIT_ROOT/plugins/agent-ios-swiftui/templates/ios-swiftui/$script"
      [ -f "$path" ] || path="$KIT_ROOT/plugins/agent-core/templates/common/$script"
      # A command, not a word: `swift` also names the language in config labels and variables.
      run ! grep -qE '(^|[^[:alnum:]_-])(plutil|xcrun|xcodebuild)([^[:alnum:]_-]|$)|(^|[^[:alnum:]_.-])swift (build|test|package|run|format)' "$path"
      ;;
    esac
  done
}
