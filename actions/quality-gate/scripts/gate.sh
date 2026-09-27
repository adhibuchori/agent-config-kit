#!/usr/bin/env bash
# The agent-config-kit quality gate for one stack. The action runs it after plan.sh and the
# toolchain steps; you can also run it by hand from a repo's root:
#
#   QG_STACK=fe-nextjs QG_BASE=origin/dev bash <kit>/actions/quality-gate/scripts/gate.sh
#
# Reads: QG_STACK, QG_BASE (a resolvable ref), QG_PM (bun|pnpm|npm|yarn|uv; default: from the
# lockfile), QG_COVERAGE_THRESHOLD (default: 0 for fe-nextjs-static and docs-nextra, else 100),
# QG_ENV_FILE (default .env.ci.example), QG_IGNORE_SCRIPTS (default true), QG_INTEGRATION_TESTS
# (default false), QG_STRICT (default true).
# Exit 0 the full gate passed, 1 a check failed (or, with strict, did not run), 2 a bad input.
set -uo pipefail

QG_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$QG_HERE/lib.sh"

QG_STACK="${QG_STACK:-}"
QG_ENV_FILE="${QG_ENV_FILE-.env.ci.example}"
QG_STRICT="${QG_STRICT:-true}"
QG_INTEGRATION_TESTS="${QG_INTEGRATION_TESTS:-false}"

if ! qg_is_stack "$QG_STACK"; then
  echo "::error::QG_STACK must be one of: $QG_STACKS (got '${QG_STACK}')" >&2
  exit 2
fi
QG_COVERAGE_THRESHOLD="${QG_COVERAGE_THRESHOLD:-$(qg_default_threshold "$QG_STACK")}"
if ! qg_valid_threshold "$QG_COVERAGE_THRESHOLD"; then
  echo "::error::coverage-threshold must be a number from 0 to 100 (got '${QG_COVERAGE_THRESHOLD}')" >&2
  exit 2
fi
if ! QG_BASE=$(qg_resolve_base "${QG_BASE:-}"); then
  echo "::error::base ref '${QG_BASE:-}' not found; fetch it (git fetch origin) or check out with fetch-depth: 0" >&2
  exit 2
fi
if [ -z "${QG_PM:-}" ]; then
  if [ "$QG_STACK" = ai-fastapi ]; then QG_PM=uv; else QG_PM=$(qg_detect_pm); fi
fi

tmp_root="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
QG_TMP=$(mktemp -d "${tmp_root%/}/quality-gate.XXXXXX") || exit 2
trap 'rm -rf "$QG_TMP"' EXIT

echo "agent-config-kit quality gate: $QG_STACK, base $QG_BASE, package manager $QG_PM, coverage floor ${QG_COVERAGE_THRESHOLD}%, strict $QG_STRICT"
qg_load_env_file "$QG_ENV_FILE" || {
  qg_summary
  exit 1
}

# shellcheck source=stacks/fe-nextjs.sh
. "$QG_HERE/stacks/${QG_STACK}.sh"
stack_gate

qg_summary
