#!/usr/bin/env bash
# Pooler check: the service's own pool behind a transaction pooler (PgBouncer). The quality gate
# runs it when the caller sets pgbouncer-tests: true, after it starts PgBouncer in front of the CI
# database; locally, run it the same way once a pooler listens where TEST_POOLER_DATABASE_URL says:
#
#   bash scripts/check/ci-env.sh bash scripts/check/pooler.sh
#
# The tests (internal/postgres/pooler_test.go, built only with the pooler tag) send many statements,
# each with its own SQL text, through the pooler and check every answer; then they compare the
# role's timeouts read through the pooler with a direct read. Fails when either address is unset.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2
export GOTOOLCHAIN=local GOFLAGS=-mod=readonly

for key in TEST_MIGRATIONS_URL TEST_DATABASE_URL TEST_POOLER_DATABASE_URL; do
  if [ -z "$(printenv "$key")" ]; then
    echo "pooler: $key is not set; run through scripts/check/ci-env.sh (.env.ci.example sets it)" >&2
    exit 1
  fi
done
go test -race -count=1 -tags pooler -run '^TestPooler' ./internal/postgres/
