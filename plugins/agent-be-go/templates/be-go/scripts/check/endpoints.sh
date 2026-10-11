#!/usr/bin/env bash
# Route-literal gate (Rule 10). Every route is an operation in api/openapi.yaml, and the generated
# server registers it, so a path such as "/api/things" belongs in generated code only. A path
# literal in hand-written Go is a route the spec does not know (or a copy of one that drifts). Test
# files may name paths; they send requests.
#
#   bash scripts/check/endpoints.sh
#
# Fails on any "/api/... string in a hand-written, non-test .go file, and when it found no
# hand-written Go to read: a scan that read nothing is not a pass.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

GENERATED='^// Code generated .* DO NOT EDIT\.$'
scanned=0
found=0
while IFS= read -r -d '' f; do
  case "$f" in *_test.go) continue ;; esac
  grep -qE "$GENERATED" "$f" && continue
  scanned=$((scanned + 1))
  # shellcheck disable=SC2016 # the backtick is Go's raw-string quote, matched literally
  if grep -nE '["`]/api(/|["`])' "$f" | sed "s#^#$f:#"; then
    found=1
  fi
done < <(find . -name '*.go' -type f -not -path './.git/*' -not -path './vendor/*' -print0)

if [ "$scanned" -eq 0 ]; then
  echo "endpoints: no hand-written Go file found; the check read nothing" >&2
  exit 1
fi
if [ "$found" -ne 0 ]; then
  echo "endpoints: a route path in hand-written code (above). Declare the operation in api/openapi.yaml, regenerate, and implement its handler (Rule 10)." >&2
  exit 1
fi
echo "endpoints: $scanned hand-written Go file(s), no route literal"
