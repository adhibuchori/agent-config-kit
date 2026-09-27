# shellcheck shell=bash
# shellcheck disable=SC2034 # sourced: strip-ai.sh, back-merge.sh and verify-strip.sh read every variable set here
# The single list of what the strip removes, and the branch names, for all three strip scripts: if
# they disagreed, the strip would half-land and the production branch would keep AI config.
#
# Word splitting is intended (one pathspec per word) and globbing is off, so a pattern such as
# `debug*.config.ts` reaches git as a pathspec instead of being expanded against the working tree.
set -f

# Agent config of every stack this kit serves, and of the other agents a repo may carry. A path that
# does not exist is skipped; nothing outside this list is ever removed.
STRIP_DEFAULT_PATHS=".agent .agents .claude .gemini .serena .impeccable _workflow-source AGENTS.md CLAUDE.md GEMINI.md SSOT.md PRODUCT.md PRODUCT.example.md DESIGN.md DESIGN.example.md skills-lock.json .mcp.json .skillspector-baseline.yaml .github/gemini.yaml .github/skills"

STRIP_PATHS="${STRIP_AI_PATHS:-$STRIP_DEFAULT_PATHS} ${STRIP_AI_EXTRA_PATHS:-}"
PROD_BRANCH="${STRIP_AI_PROD_BRANCH:-prod}"
DEV_BRANCH="${STRIP_AI_DEV_BRANCH:-dev}"
LIST="${STRIP_AI_LIST:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/stripped-paths.txt}"

# Bot identity, passed per invocation with -c so it never touches .git/config. A runner has no git
# identity of its own, and git refuses to commit or merge without one.
GIT_BOT_IDENTITY=(-c user.name="github-actions[bot]" -c user.email="github-actions[bot]@users.noreply.github.com")

strip_ai_validate() {
  local b w
  for b in "$PROD_BRANCH" "$DEV_BRANCH"; do
    if ! git check-ref-format --branch "$b" >/dev/null 2>&1; then
      echo "::error::'$b' is not a valid branch name" >&2
      return 2
    fi
  done
  if [ "$PROD_BRANCH" = "$DEV_BRANCH" ]; then
    echo "::error::prod-branch and dev-branch are both '$PROD_BRANCH'; the strip needs two branches" >&2
    return 2
  fi
  for w in $STRIP_PATHS; do
    case "$w" in
    -* | *..* | /*)
      echo "::error::'$w' is not a repo-relative path or pattern" >&2
      return 2
      ;;
    esac
  done
}
