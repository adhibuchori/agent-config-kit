#!/usr/bin/env bash
# The pooler tier: tests/pooler runs the service's own pool through PgBouncer in transaction mode,
# where prepared statements, startup parameters and session settings break without an error. The
# quality gate starts PgBouncer and runs this when the caller sets `pgbouncer-tests: true`; the
# tests are #[ignore] everywhere else. It reuses the coverage run's build (--no-report).
#
#   TEST_POOLER_DATABASE_URL=postgres://app_rw@127.0.0.1:6432/app_test?sslmode=disable \
#     bash scripts/check/pooler.sh
#
# The role in that URL is the service's (app_rw, db/roles.sql), so its timeouts are the ones read.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

export RUSTUP_AUTO_INSTALL=0
if [ -z "${TEST_POOLER_DATABASE_URL:-}" ]; then
  echo "pooler: TEST_POOLER_DATABASE_URL is not set: point it at PgBouncer in front of the test database" >&2
  exit 1
fi
exec cargo llvm-cov nextest --locked --no-report --run-ignored only --test pooler
