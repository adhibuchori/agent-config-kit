# shellcheck shell=bash
# be-axum (agent-be-axum): a Rust axum + sqlx API on PostgreSQL. Sourced by gate.sh after lib.sh.
#
# The workflow installs the toolchain rust-toolchain.toml names (and then forbids rustup from
# installing anything else), the pinned cargo-llvm-cov, cargo-nextest, cargo-deny, squawk and
# sqlx-cli (install-release.sh), and starts PostgreSQL 18.6 on 127.0.0.1:5432. Then: cargo fetch
# --locked; db/roles.sql; the repo's gates.list (rustfmt, clippy, cargo policy, the source checks,
# migrations, the kit checks, tests with coverage); the coverage floor from coverage/lcov.info; every
# migration from zero with sqlx; the .sqlx query cache against that schema; the foreign-key and
# INVALID-index catalog checks; the optional PgBouncer check; the migrations against the base branch
# and squawk over the new ones; the pool settings; a committed .env; gitleaks over the PR's commits;
# cargo deny; a changed skill; the OpenAPI spec export; the release build; the Docker build when
# there is a Dockerfile. Every cargo call is --locked.

be_axum_install() {
  qg_step "Install Dependencies (cargo fetch --locked)"
  if [ ! -f rust-toolchain.toml ]; then
    qg_fail "no rust-toolchain.toml: the be-axum gate builds with exactly the toolchain it names"
    return 1
  fi
  if ! git ls-files --error-unmatch Cargo.lock >/dev/null 2>&1; then
    qg_fail "Cargo.lock is not committed: every cargo call in the gate is --locked"
    return 1
  fi
  # A missing toolchain or component is an error, never a download in the middle of a check.
  export RUSTUP_AUTO_INSTALL=0
  if ! cargo fetch --locked; then
    qg_fail "Install Dependencies failed (cargo fetch --locked)"
    return 1
  fi
}

be_axum_sqlx_ready() {
  command -v sqlx >/dev/null 2>&1 && return
  echo "sqlx-cli is not installed on this runner"
  return 1
}

# --no-dotenv: a .env file on the runner never chooses the database.
be_axum_sqlx_up() {
  DATABASE_URL="$QG_MIGRATIONS_URL" sqlx migrate run --no-dotenv --source migrations
}

# The query cache (.sqlx/) against the schema the migrations just built: a query edited without
# `cargo sqlx prepare`, or a migration that changes a type a query reads, fails here.
be_axum_query_cache() {
  local name="Query Cache Check (cargo sqlx prepare --check)"
  qg_step "$name"
  case "${QG_DB_STATE:-skipped}" in
  ok) ;;
  off) qg_db_off_note && return ;;
  none) echo "No migration yet; nothing to check" && return ;;
  failed) echo "The migrations failed above; nothing to check" && return ;;
  *)
    qg_skip "$name" "the migrations did not run"
    return
    ;;
  esac
  DATABASE_URL="$QG_MIGRATIONS_URL" cargo sqlx prepare --check --no-dotenv -- --all-targets ||
    qg_fail "the .sqlx query cache is stale: run cargo sqlx prepare against a migrated database and commit .sqlx/"
}

# The pool settings agent-be-axum's AGENTS.md hands to this gate (Rule 17), read from
# src/platform/db.rs with // comments stripped: max_connections (not 1 or 2), acquire_timeout,
# max_lifetime, and extra_float_digits(None), without which PgBouncer refuses every connection.
be_axum_hardening() {
  local name="Runtime Settings Check (pool)" db=src/platform/db.rs code bad=0 want
  qg_step "$name"
  if ! qg_db_on; then
    qg_db_off_note
    return
  fi
  if [ ! -f "$db" ]; then
    qg_fail "$name reads $db (agent-be-axum's layout); it is missing"
    return
  fi
  code=$(sed -E 's://.*$::' "$db")
  for want in 'max_connections(' 'acquire_timeout(' 'max_lifetime(' 'extra_float_digits(None)'; do
    if ! grep -qF "$want" <<<"$code"; then
      echo "::error file=$db::the pool never calls ${want%(*} as Rule 17 asks"
      bad=1
    fi
  done
  if grep -qE 'max_connections\([[:space:]]*[12][[:space:]]*\)' <<<"$code"; then
    echo "::error file=$db::a pool of 1 or 2 connections serializes every request (Rule 17)"
    bad=1
  fi
  if [ "$bad" -ne 0 ]; then
    qg_fail "$name"
  else
    echo "Clean"
  fi
}

be_axum_deny() {
  qg_step "Dependency Audit (cargo deny check)"
  if [ ! -f deny.toml ]; then
    qg_skip "Dependency Audit" "deny.toml is missing: run /agent-be-axum:setup"
    return
  fi
  if ! command -v cargo-deny >/dev/null 2>&1; then
    qg_skip "Dependency Audit" "cargo-deny is not installed on this runner"
    return
  fi
  cargo deny --locked check || qg_fail "cargo deny found an advisory, a banned or duplicate crate, a license or a source deny.toml does not allow"
}

# openapi.json feeds the generated clients (the iOS app among them). src/bin/openapi.rs writes it
# from the code; a stale or uncommitted file fails here, as be-hono's spec:export does.
be_axum_spec_drift() {
  qg_step "OpenAPI Spec Drift Check"
  if [ ! -f src/bin/openapi.rs ]; then
    echo "No src/bin/openapi.rs; nothing to compare"
    return
  fi
  if ! cargo run --locked --quiet --bin openapi; then
    qg_fail "cargo run --bin openapi failed, so openapi.json was not regenerated"
  elif [ -n "$(git status --porcelain -- openapi.json)" ]; then
    git --no-pager diff -- openapi.json | head -40 | qg_quote
    qg_fail "openapi.json is stale or uncommitted: run cargo run --bin openapi and commit it"
  else
    echo "Clean"
  fi
}

stack_gate() {
  be_axum_install || return 0
  qg_db_roles
  qg_gates
  qg_coverage_floor
  qg_db_migrate "Migrations From Zero (sqlx migrate run)" migrations be_axum_sqlx_up be_axum_sqlx_ready
  be_axum_query_cache
  qg_db_catalog
  qg_pgbouncer_tests
  qg_db_repo_script "Migrations Against the Base Branch" scripts/check/migrations.sh --base "$QG_BASE"
  qg_squawk migrations
  be_axum_hardening
  qg_env_committed
  qg_gitleaks
  be_axum_deny
  qg_skill_scan
  be_axum_spec_drift
  qg_run "Production Build (cargo build --locked --release)" cargo build --locked --release
  qg_docker_build "Docker Build"
}
