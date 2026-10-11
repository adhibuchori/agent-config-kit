# shellcheck shell=bash
# be-go (agent-be-go): a Go net/http API on PostgreSQL. Sourced by gate.sh after lib.sh.
#
# The workflow sets up Go from go.mod, installs the pinned golangci-lint and squawk
# (install-release.sh) and starts PostgreSQL 18.6 on 127.0.0.1:5432. Then: go mod download and
# verify; db/roles.sql; the repo's gates.list (format, lint, build, tidy, generated code, migrations,
# endpoints, the kit checks, tests with coverage); the coverage floor from coverage/coverage.out;
# every migration from zero with goose; the foreign-key and INVALID-index catalog checks; the
# optional PgBouncer check; the migrations against the base branch and squawk over the new ones; the
# runtime settings (pool and server); a committed .env; gitleaks over the PR's commits; govulncheck;
# a changed skill; go build -trimpath; the Docker build when there is a Dockerfile.
#
# go.mod pins oapi-codegen, sqlc, goose and govulncheck as `tool` lines, so `go tool` runs exactly
# those; golangci-lint is a checksummed release binary, as its own docs recommend.

be_go_install() {
  # Nothing downloads a toolchain behind the gate's back, and nothing rewrites go.mod or go.sum.
  export GOTOOLCHAIN=local GOFLAGS=-mod=readonly
  qg_step "Install Dependencies (go mod download, go mod verify)"
  if [ ! -f go.mod ]; then
    qg_fail "no go.mod: the be-go gate builds a Go module"
    return 1
  fi
  if ! go mod download || ! go mod verify; then
    qg_fail "Install Dependencies failed (go mod download or go mod verify)"
    return 1
  fi
}

be_go_goose_ready() {
  go tool -n goose >/dev/null 2>&1 && return
  echo "go.mod has no tool line for goose (github.com/pressly/goose/v3/cmd/goose): run /agent-be-go:setup"
  return 1
}

be_go_goose_up() {
  go tool goose -dir db/migrations postgres "$QG_MIGRATIONS_URL" up
}

# The settings agent-be-go's AGENTS.md hands to this gate (Rules 17 and 18), read with // comments
# stripped from the non-test files: the pool in internal/postgres sets MaxConns (not 1 or 2),
# MaxConnLifetime and ConnectTimeout; the server in cmd/api or internal/httpapi sets all four
# timeouts; internal/httpapi caps request bodies with MaxBytesReader.
be_go_code() { # $@ folders: their non-test .go files, comments stripped
  find "$@" -name '*.go' ! -name '*_test.go' -type f 2>/dev/null | sort |
    while IFS= read -r f; do sed -E 's://.*$::' "$f"; done
}

be_go_hardening() {
  qg_step "Runtime Settings Check (pool and server)"
  local pool server httpapi bad=0 want
  server=$(be_go_code cmd/api internal/httpapi)
  httpapi=$(be_go_code internal/httpapi)
  if [ -z "$server" ]; then
    qg_fail "Runtime Settings Check reads cmd/api and internal/httpapi (agent-be-go's layout); neither has Go code"
    return
  fi
  for want in ReadHeaderTimeout ReadTimeout WriteTimeout IdleTimeout; do
    if ! grep -qw "$want" <<<"$server"; then
      echo "::error::the http.Server never sets $want (Rule 18): a slow client can hold a connection open"
      bad=1
    fi
  done
  if ! grep -qF 'MaxBytesReader' <<<"$httpapi"; then
    echo "::error::internal/httpapi never caps a request body with http.MaxBytesReader (Rule 18)"
    bad=1
  fi
  if qg_db_on; then
    pool=$(be_go_code internal/postgres)
    for want in MaxConns MaxConnLifetime ConnectTimeout; do
      if ! grep -qw "$want" <<<"$pool"; then
        echo "::error::internal/postgres never sets $want on the pool (Rule 17)"
        bad=1
      fi
    done
    if grep -qE '(^|[^[:alnum:]_])MaxConns[[:space:]]*=[[:space:]]*[12]([^0-9]|$)' <<<"$pool"; then
      echo "::error::a pool of 1 or 2 connections serializes every request (Rule 17)"
      bad=1
    fi
  fi
  if [ "$bad" -ne 0 ]; then
    qg_fail "Runtime Settings Check"
  else
    echo "Clean"
  fi
}

# govulncheck reports only the vulnerable code this module actually reaches. Text mode: exit 3 means
# findings (JSON mode always exits 0, so it is never used to gate).
be_go_vulncheck() {
  qg_step "Vulnerability Scan (govulncheck)"
  if ! go tool -n govulncheck >/dev/null 2>&1; then
    qg_skip "Vulnerability Scan" "go.mod has no tool line for govulncheck (golang.org/x/vuln/cmd/govulncheck): run /agent-be-go:setup"
    return
  fi
  go tool govulncheck ./...
  case $? in
  0) ;;
  3) qg_fail "govulncheck found a vulnerability the code reaches" ;;
  *) qg_fail "govulncheck could not finish" ;;
  esac
}

stack_gate() {
  be_go_install || return 0
  qg_db_roles
  qg_gates
  qg_coverage_floor
  qg_db_migrate "Migrations From Zero (goose up)" db/migrations be_go_goose_up be_go_goose_ready
  qg_db_catalog
  qg_pgbouncer_tests
  qg_db_repo_script "Migrations Against the Base Branch" scripts/check/migrations.sh --base "$QG_BASE"
  qg_squawk db/migrations goose
  be_go_hardening
  qg_env_committed
  qg_gitleaks
  be_go_vulncheck
  qg_skill_scan
  qg_run "Production Build (go build -trimpath ./...)" go build -trimpath ./...
  qg_docker_build "Docker Build"
}
