#!/usr/bin/env bash
# Regenerates the API client from the backend's spec copy (AGENTS.md Rule 11). Runs
# swift-openapi-generator's command plugin, at the exact version Packages/AppCore/Package.resolved
# pins, on Packages/AppCore/Sources/APIClient/openapi.json with openapi-generator-config.yaml beside
# it, and rewrites Packages/AppCore/Sources/APIClient/GeneratedSources. The generated files and the
# spec copy are committed; the generated-guard hook refuses hand edits to either. The quality gate
# runs the same plugin with the same flags and fails on any difference.
#
#   bash scripts/ios/api-client.sh           regenerate, then list what changed
#   bash scripts/ios/api-client.sh --check   regenerate, and fail when the committed client differs
#
# Exit 0 done (or no drift), 1 drift, 2 no spec copy, no Swift toolchain or a bad argument.
set -euo pipefail
cd "$(dirname "$0")/../.." || exit 2

PKG=Packages/AppCore
SRC="$PKG/Sources/APIClient"
CHECK=0
case "${1:-}" in
'') ;;
--check) CHECK=1 ;;
*)
  echo "usage: bash scripts/ios/api-client.sh [--check]" >&2
  exit 2
  ;;
esac

spec=""
for f in "$SRC/openapi.json" "$SRC/openapi.yaml" "$SRC/openapi.yml"; do
  [ -f "$f" ] && spec="$f" && break
done
[ -n "$spec" ] || {
  echo "api-client: no spec copy in $SRC/; copy the backend's exported openapi.json there first" >&2
  exit 2
}
command -v swift >/dev/null 2>&1 || {
  echo "api-client: swift not found; this runs on a Mac with Xcode" >&2
  exit 2
}

swift package --package-path "$PKG" --force-resolved-versions \
  --allow-writing-to-package-directory generate-code-from-openapi --target APIClient

if [ "$CHECK" -eq 1 ]; then
  if [ -n "$(git status --porcelain -- "$SRC")" ]; then
    git status --short -- "$SRC" >&2
    echo "api-client: the committed client differs from what $spec generates: run bash scripts/ios/api-client.sh and commit" >&2
    exit 1
  fi
  echo "api-client: the committed client matches $spec"
  exit 0
fi
git status --short -- "$SRC"
