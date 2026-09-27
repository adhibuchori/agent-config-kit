#!/usr/bin/env bash
# Removes the agent config (strip-paths.sh) from the production branch and pushes the strip commit.
# Run from a checkout of that branch with full history and a token that may push to it.
set -euo pipefail

# shellcheck source=strip-paths.sh
. "$(dirname "${BASH_SOURCE[0]}")/strip-paths.sh"
strip_ai_validate

current=$(git rev-parse --abbrev-ref HEAD)
if [ "$current" != "$PROD_BRANCH" ]; then
  echo "::error::the checkout is on '$current'; check out '$PROD_BRANCH' (actions/checkout with ref: $PROD_BRANCH)" >&2
  exit 2
fi

# shellcheck disable=SC2086 # one pathspec per word
git rm -r -q --cached --ignore-unmatch -- $STRIP_PATHS

# What was really tracked, not the wishlist: verify-strip.sh asserts against this list, and back-merge
# relies on the same paths.
git diff --cached --name-only --diff-filter=D >"$LIST"
echo "paths stripped: $(wc -l <"$LIST" | tr -d ' ')"

if git diff --cached --quiet; then
  echo "No agent config is tracked on $PROD_BRANCH; nothing to strip."
  exit 0
fi

# No skip-CI marker: nothing here runs on a push, so a marker would prevent nothing, and on the head
# of a pull request it would stop that pull request's checks.
git "${GIT_BOT_IDENTITY[@]}" commit -q -m "chore: strip AI and agent config from ${PROD_BRANCH}"

# git rm --cached leaves the stripped files untracked, and a rebase refuses to overwrite them.
# shellcheck disable=SC2086 # one pathspec per word
git clean -fdq -- $STRIP_PATHS || true

# Anything else pushing to the branch makes a rejected push expected rather than fatal.
for attempt in 1 2 3; do
  if git "${GIT_BOT_IDENTITY[@]}" pull -q --rebase origin "$PROD_BRANCH" && git push -q origin "HEAD:refs/heads/${PROD_BRANCH}"; then
    echo "$PROD_BRANCH no longer tracks the agent config."
    exit 0
  fi
  # A half-finished rebase would make every later attempt fail with "rebase in progress".
  git rebase --abort 2>/dev/null || true
  # shellcheck disable=SC2086 # one pathspec per word
  git clean -fdq -- $STRIP_PATHS || true
  echo "push rejected (attempt ${attempt}/3); ${PROD_BRANCH} moved underneath us, retrying."
  sleep 5
done

echo "::error::could not push the strip commit after 3 attempts" >&2
exit 1
