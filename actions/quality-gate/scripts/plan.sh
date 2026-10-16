#!/usr/bin/env bash
# Plans a quality-gate run before any toolchain is installed: validates the inputs, resolves the base
# the diff checks compare against, picks the package manager from the lockfile, and says which
# toolchains and pinned tools the later steps set up. Writes key=value lines to $GITHUB_OUTPUT (or
# stdout off a runner). Exit 2 on a bad input, so a typo in a caller fails loudly instead of gating
# nothing.
#
# Reads: QG_STACK, QG_BASE_REF, QG_PACKAGE_MANAGER, QG_COVERAGE_THRESHOLD, QG_STRICT, QG_PHASE,
# QG_DATABASE, QG_PGBOUNCER_TESTS, QG_PGBOUNCER_MAX_PREPARED.
set -uo pipefail

QG_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$QG_HERE/lib.sh"

stack="${QG_STACK:-}"
want_pm="${QG_PACKAGE_MANAGER:-auto}"
phase="${QG_PHASE:-all}"
database="${QG_DATABASE:-true}"
pgbouncer="${QG_PGBOUNCER_TESTS:-false}"
max_prepared="${QG_PGBOUNCER_MAX_PREPARED:-200}"

bad() {
  echo "::error::$1" >&2
  exit 2
}

qg_is_stack "$stack" || bad "stack must be one of: $QG_STACKS (got '${stack}')"
threshold="${QG_COVERAGE_THRESHOLD:-$(qg_default_threshold "$stack")}"
qg_valid_threshold "$threshold" || bad "coverage-threshold must be a number from 0 to 100 (got '${threshold}')"
case "${QG_STRICT:-true}" in true | false) ;; *) bad "strict must be true or false (got '${QG_STRICT}')" ;; esac
case "$database" in true | false) ;; *) bad "database must be true or false (got '${database}')" ;; esac
case "$pgbouncer" in true | false) ;; *) bad "pgbouncer-tests must be true or false (got '${pgbouncer}')" ;; esac
case "$max_prepared" in '' | *[!0-9]*)
  bad "pgbouncer-max-prepared-statements must be a whole number of 0 or more (got '${max_prepared}')"
  ;;
esac
# Only the iOS gate is split: a Linux job for the static checks, then a macOS job for the build.
if [ "$stack" = ios-swiftui ]; then
  case "$phase" in static | build | all) ;; *) bad "phase must be static, build or all (got '${phase}')" ;; esac
elif [ "$phase" != all ]; then
  bad "phase splits only the ios-swiftui gate; $stack takes phase all (got '${phase}')"
fi
if [ "$pgbouncer" = true ]; then
  case "$stack" in be-go | be-axum) ;; *) bad "pgbouncer-tests is for be-go and be-axum, whose gate runs PostgreSQL ($stack does not)" ;; esac
  [ "$database" = true ] || bad "pgbouncer-tests needs database: true (PgBouncer sits in front of the gate's PostgreSQL)"
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  bad "the working directory is not a git checkout; check out the repository first"
fi
if ! base=$(qg_resolve_base "${QG_BASE_REF:-}"); then
  bad "base '${QG_BASE_REF:-}' not found. Run the gate on a pull_request event (it uses github.base_ref), check out with fetch-depth: 0, or pass base-ref."
fi

if [ "$stack" = ai-fastapi ]; then
  case "$want_pm" in auto | uv) pm=uv ;; *) bad "ai-fastapi runs on uv; package-manager must be auto or uv (got '${want_pm}')" ;; esac
elif qg_js_stack "$stack"; then
  case "$want_pm" in
  auto) pm=$(qg_detect_pm) ;;
  bun | pnpm | npm | yarn) pm="$want_pm" ;;
  *) bad "package-manager must be auto, bun, pnpm, npm or yarn (got '${want_pm}')" ;;
  esac
else
  [ "$want_pm" = auto ] || bad "$stack installs no JavaScript dependencies; package-manager must be auto (got '${want_pm}')"
  pm=none
fi

# Which job runs the pull-request checks (.env, gitleaks, the skill scan): every gate except the
# iOS macOS job, which runs after the static job already did.
pr_checks=true
[ "$stack" = ios-swiftui ] && [ "$phase" = build ] && pr_checks=false

# uv: the Python stack, and any pull request that changes a skill, command, subagent or hook (the
# SkillSpector build installs with uv).
uv=false
[ "$stack" = ai-fastapi ] && uv=true
if [ "$pr_checks" = true ] && [ -f scripts/check/skills.sh ] &&
  ! git diff --quiet "${base}...HEAD" -- "${QG_SKILL_PATHS[@]}" 2>/dev/null; then
  uv=true
fi
bun=false
[ "$pm" = bun ] && bun=true
corepack=false
case "$pm" in pnpm | yarn) corepack=true ;; esac

# The pinned tools install-release.sh sets up (tools.lock), and the language toolchains.
go=false rust=false tools=""
case "$stack" in
be-go)
  go=true
  tools="golangci-lint"
  [ "$database" = true ] && tools="$tools squawk"
  ;;
be-axum)
  rust=true
  tools="cargo-llvm-cov cargo-nextest cargo-deny"
  [ "$database" = true ] && tools="$tools squawk sqlx-cli"
  ;;
ios-swiftui)
  # The static job runs no SwiftLint: swiftlint-static aborts on a custom rule (it needs SourceKit).
  [ "$phase" = static ] || tools="swiftlint periphery"
  ;;
esac

out="${GITHUB_OUTPUT:-/dev/stdout}"
{
  echo "stack=$stack"
  echo "base=$base"
  echo "coverage-threshold=$threshold"
  echo "pm=$pm"
  echo "phase=$phase"
  echo "node=true"
  echo "bun=$bun"
  echo "uv=$uv"
  echo "corepack=$corepack"
  echo "go=$go"
  echo "rust=$rust"
  # Installed in every job: the gates.list line bash scripts/check/secrets.sh needs it wherever the
  # list runs, the iOS macOS job included. Only the PR-check job scans the pull request's commits.
  echo "gitleaks=true"
  echo "tools=$tools"
} >>"$out"
echo "quality gate plan: stack=$stack phase=$phase base=$base package-manager=$pm bun=$bun uv=$uv corepack=$corepack go=$go rust=$rust gitleaks=true tools=${tools:-none}" >&2
