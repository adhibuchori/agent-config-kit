#!/usr/bin/env bash
# COVER: every test, with coverage, then each file at 100% of its lines and functions
# (.claude/rules/rust/coverage.md). One tier with a real database: the #[sqlx::test] tests need
# PostgreSQL at DATABASE_URL, as a role that may create databases. gates.list runs this through
# scripts/check/ci-env.sh, so DATABASE_URL is the one in .env.ci.example and nothing else from your
# shell reaches the tests (not even RUSTUP_AUTO_INSTALL, which this script sets itself; SQLX_OFFLINE
# comes from .cargo/config.toml). The pooler tests (#[ignore]) run in CI only: pooler.sh.
#
#   bash scripts/check/ci-env.sh bash scripts/check/coverage.sh
#
# Exemptions: scripts/check/coverage-exempt.txt, one `<glob>  # composition root: <why>` per line.
# Files under tests/ and *_tests.rs are left out by cargo-llvm-cov itself. Writes
# coverage/lcov.info, which the quality gate's coverage floor reads too.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

# A missing toolchain or component is an error, never a download in the middle of the tests.
export RUSTUP_AUTO_INSTALL=0
if [ -z "${DATABASE_URL:-}" ]; then
  echo "coverage: DATABASE_URL is not set; list it in .env.ci.example and run this through scripts/check/ci-env.sh" >&2
  exit 1
fi
regex="$(node scripts/check/coverage-per-file.mjs ignore-regex)" || exit 2
# llvm-cov does not create the folder, and would fail only after every test ran.
mkdir -p coverage
if ! cargo llvm-cov nextest --locked --ignore-filename-regex "$regex" --lcov --output-path coverage/lcov.info; then
  echo "coverage: a test failed. A #[sqlx::test] that cannot connect needs PostgreSQL 18 at DATABASE_URL, for example:" >&2
  echo "  docker run --rm -d -p 5432:5432 -e POSTGRES_HOST_AUTH_METHOD=trust postgres:18.6" >&2
  exit 1
fi
exec node scripts/check/coverage-per-file.mjs check coverage/lcov.info
