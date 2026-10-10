#!/usr/bin/env bash
# Coverage gate (Rule 25, .claude/rules/go/coverage.md): every package's tests, with the race
# detector, against a real PostgreSQL, then 100% of statements in every hand-written file.
# gates.list runs it through scripts/check/ci-env.sh, so the tests get CI's variables
# (TEST_DATABASE_URL from .env.ci.example) and nothing from your shell.
#
#   bash scripts/check/ci-env.sh bash scripts/check/coverage.sh
#
# Go measures statements only and has no way to leave a file out, so the raw profile is filtered
# first: files whose header says `// Code generated ... DO NOT EDIT.` and the files
# scripts/check/coverage-exempt.txt lists, each with its reason, are dropped. A package with no test
# is in the profile at 0%. The filtered profile, coverage/coverage.out, is what the quality gate's
# coverage floor reads.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2
# ci-env.sh starts the tests with an empty environment, so the Go settings the gate relies on are
# set here: no toolchain download, and go.mod and go.sum never rewritten.
export GOTOOLCHAIN=local GOFLAGS=-mod=readonly

if [ -z "${TEST_DATABASE_URL:-}" ]; then
  echo "coverage: TEST_DATABASE_URL is not set. Run the tests through scripts/check/ci-env.sh, which" \
    "reads it from .env.ci.example, with PostgreSQL 18 up and db/roles.sql applied" \
    "(.claude/rules/backend/testing.md)." >&2
  exit 1
fi
mkdir -p coverage
# -count=1: a cached result says nothing about the database the tests would meet now.
go test -race -count=1 -covermode=atomic -coverprofile=coverage/raw.out ./... || exit 1
node scripts/check/coverage-per-file.mjs filter-go coverage/raw.out coverage/coverage.out || exit 1
node scripts/check/coverage-per-file.mjs check coverage/coverage.out
