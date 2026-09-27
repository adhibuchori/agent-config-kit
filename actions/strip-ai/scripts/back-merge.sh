#!/usr/bin/env bash
# Merges the production branch back into the development branch after a strip, keeping the
# development branch's agent config: the merge would otherwise delete it there too.
set -euo pipefail

# shellcheck source=strip-paths.sh
. "$(dirname "${BASH_SOURCE[0]}")/strip-paths.sh"
strip_ai_validate

# The checkout below refuses to overwrite these untracked leftovers of the strip.
# shellcheck disable=SC2086 # one pathspec per word
git clean -fdq -- $STRIP_PATHS || true

git fetch -q origin "$DEV_BRANCH" "$PROD_BRANCH"
git checkout -q -B "$DEV_BRANCH" "origin/$DEV_BRANCH"
BEFORE=$(git rev-parse HEAD)

# Settle the genuine no-op first, so that below a missing MERGE_HEAD can only mean the merge failed.
if git merge-base --is-ancestor "origin/$PROD_BRANCH" HEAD; then
  echo "$PROD_BRANCH is already part of $DEV_BRANCH; nothing to back-merge."
  exit 0
fi

git "${GIT_BOT_IDENTITY[@]}" merge -q --no-commit --no-ff "origin/$PROD_BRANCH" || true

# Put back what the merge would delete: that is the config the strip removed, and the development
# branch is where it belongs.
git diff --cached --diff-filter=D --name-only "$BEFORE" | while IFS= read -r f; do
  [ -n "$f" ] && git checkout -q "$BEFORE" -- "$f"
done

# modify/delete conflicts on those paths: keep the development branch's copy.
git diff --name-only --diff-filter=U | while IFS= read -r f; do
  [ -n "$f" ] && git checkout -q "$BEFORE" -- "$f" && git add -- "$f"
done

# Anything still conflicted is a real content clash, not strip fallout. Stop rather than push a guess.
remaining=$(git diff --name-only --diff-filter=U)
if [ -n "$remaining" ]; then
  echo "::error::the back-merge hit conflicts outside the stripped paths; resolve them by hand:" >&2
  printf '%s\n' "$remaining" >&2
  git merge --abort || true
  exit 1
fi

if [ ! -f "$(git rev-parse --git-dir)/MERGE_HEAD" ]; then
  echo "::error::merging origin/$PROD_BRANCH left no MERGE_HEAD, so the back-merge never ran; see the merge output above" >&2
  exit 1
fi

git "${GIT_BOT_IDENTITY[@]}" commit -q -m "chore: back-merge ${PROD_BRANCH} into ${DEV_BRANCH} after the AI config strip"

# Merge, never rebase: rebase drops the merge commit above, and the push then reports nothing to do.
for attempt in 1 2 3; do
  if git "${GIT_BOT_IDENTITY[@]}" pull -q --no-rebase --no-edit origin "$DEV_BRANCH" && git push -q origin "HEAD:refs/heads/${DEV_BRANCH}"; then
    echo "$DEV_BRANCH now contains $PROD_BRANCH and keeps its agent config."
    exit 0
  fi
  git merge --abort 2>/dev/null || true
  echo "push rejected (attempt ${attempt}/3); ${DEV_BRANCH} moved underneath us, retrying."
  sleep 5
done

echo "::error::could not push the back-merge after 3 attempts" >&2
exit 1
