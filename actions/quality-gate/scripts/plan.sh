#!/usr/bin/env bash
# Plans a quality-gate run before any toolchain is installed: validates the inputs, resolves the base
# the diff checks compare against, picks the package manager from the lockfile, and says which
# toolchains the later steps set up. Writes key=value lines to $GITHUB_OUTPUT (or stdout off a
# runner). Exit 2 on a bad input, so a typo in a caller fails loudly instead of gating nothing.
#
# Reads: QG_STACK, QG_BASE_REF, QG_PACKAGE_MANAGER, QG_COVERAGE_THRESHOLD, QG_STRICT.
set -uo pipefail

QG_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$QG_HERE/lib.sh"

stack="${QG_STACK:-}"
want_pm="${QG_PACKAGE_MANAGER:-auto}"

if ! qg_is_stack "$stack"; then
  echo "::error::stack must be one of: $QG_STACKS (got '${stack}')" >&2
  exit 2
fi
threshold="${QG_COVERAGE_THRESHOLD:-$(qg_default_threshold "$stack")}"
if ! qg_valid_threshold "$threshold"; then
  echo "::error::coverage-threshold must be a number from 0 to 100 (got '${threshold}')" >&2
  exit 2
fi
case "${QG_STRICT:-true}" in true | false) ;; *)
  echo "::error::strict must be true or false (got '${QG_STRICT}')" >&2
  exit 2
  ;;
esac

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "::error::the working directory is not a git checkout; check out the repository first" >&2
  exit 2
fi
if ! base=$(qg_resolve_base "${QG_BASE_REF:-}"); then
  echo "::error::base '${QG_BASE_REF:-}' not found. Run the gate on a pull_request event (it uses github.base_ref), check out with fetch-depth: 0, or pass base-ref." >&2
  exit 2
fi

if [ "$stack" = ai-fastapi ]; then
  case "$want_pm" in auto | uv) pm=uv ;; *)
    echo "::error::ai-fastapi runs on uv; package-manager must be auto or uv (got '${want_pm}')" >&2
    exit 2
    ;;
  esac
else
  case "$want_pm" in
  auto) pm=$(qg_detect_pm) ;;
  bun | pnpm | npm | yarn) pm="$want_pm" ;;
  *)
    echo "::error::package-manager must be auto, bun, pnpm, npm or yarn (got '${want_pm}')" >&2
    exit 2
    ;;
  esac
fi

# uv: the Python stack, and any pull request that changes a skill, command, subagent or hook (the
# SkillSpector build installs with uv).
uv=false
[ "$stack" = ai-fastapi ] && uv=true
if [ -f scripts/check/skills.sh ] && ! git diff --quiet "${base}...HEAD" -- "${QG_SKILL_PATHS[@]}" 2>/dev/null; then
  uv=true
fi
bun=false
[ "$pm" = bun ] && bun=true
corepack=false
case "$pm" in pnpm | yarn) corepack=true ;; esac

out="${GITHUB_OUTPUT:-/dev/stdout}"
{
  echo "stack=$stack"
  echo "base=$base"
  echo "coverage-threshold=$threshold"
  echo "pm=$pm"
  echo "node=true"
  echo "bun=$bun"
  echo "uv=$uv"
  echo "corepack=$corepack"
} >>"$out"
echo "quality gate plan: stack=$stack base=$base package-manager=$pm bun=$bun uv=$uv corepack=$corepack" >&2
