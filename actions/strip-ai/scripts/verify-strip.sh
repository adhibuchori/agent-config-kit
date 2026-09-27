#!/usr/bin/env bash
# Asserts the production branch lost every stripped path and, when the back-merge ran, that the
# development branch still has each file the strip removed. A strip that also emptied the
# development branch would otherwise pass unnoticed.
set -euo pipefail

# shellcheck source=strip-paths.sh
. "$(dirname "${BASH_SOURCE[0]}")/strip-paths.sh"
strip_ai_validate

git fetch -q origin "$PROD_BRANCH"

# git diff against the empty tree lists every file the branch tracks under the pathspecs, globs
# included (git ls-tree would take a pattern such as debug*.config.ts literally).
empty=$(git hash-object -t tree /dev/null)
# shellcheck disable=SC2086 # one pathspec per word
remaining=$(git diff --name-only "$empty" "origin/$PROD_BRANCH" -- $STRIP_PATHS)
if [ -n "$remaining" ]; then
  echo "::error::these paths are still tracked on $PROD_BRANCH after the strip:" >&2
  printf '%s\n' "$remaining" >&2
  exit 1
fi
echo "$PROD_BRANCH tracks none of the stripped paths."

if [ "${STRIP_AI_BACK_MERGE:-true}" != "true" ]; then
  echo "back-merge is off; $DEV_BRANCH was not checked."
  exit 0
fi
[ -s "$LIST" ] || {
  echo "Nothing was stripped."
  exit 0
}
git fetch -q origin "$DEV_BRANCH"
missing=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  git cat-file -e "origin/${DEV_BRANCH}:${f}" 2>/dev/null || missing="${missing}"$'\n'"  $f"
done <"$LIST"
if [ -n "$missing" ]; then
  printf '::error::stripped from %s but also missing on %s:%s\n' "$PROD_BRANCH" "$DEV_BRANCH" "${missing//$'\n'/%0A}" >&2
  exit 1
fi
echo "$DEV_BRANCH still has every stripped path."
