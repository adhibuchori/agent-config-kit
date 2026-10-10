#!/usr/bin/env bash
# Generated-code gate. The server (internal/httpapi/api.gen.go), the contract clients read
# (api/openapi.json) and the query code (internal/postgres/db/, once db/queries holds SQL) are
# generated and committed. This regenerates them in a scratch copy of the repo and fails when a
# committed output differs, is missing, or is left over: the spec or a query changed and nobody
# regenerated. Then it holds the queries to the vet rules in sqlc.yaml (a list query without LIMIT)
# and refuses SELECT * in db/queries (Rule 14).
#
#   bash scripts/check/generated.sh           check, read-only
#   bash scripts/check/generated.sh --write   regenerate in place, then stop
#
# The generators are the `tool` lines of go.mod, so their versions are pinned there:
# `go generate ./...` runs oapi-codegen and the spec export, and sqlc runs when db/queries holds a
# .sql file (sqlc refuses an empty folder).
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2
# Nothing downloads a toolchain, and go.mod and go.sum are never rewritten.
export GOTOOLCHAIN=local GOFLAGS=-mod=readonly

GENERATED='^// Code generated .* DO NOT EDIT\.$'

has_queries() {
  [ -d "$1/db/queries" ] && [ -n "$(find "$1/db/queries" -name '*.sql' -type f 2>/dev/null | head -1)" ]
}

# regenerate <dir>: every generator, in that copy of the repo.
regenerate() {
  (cd "$1" && go generate ./...) || return 1
  if has_queries "$1"; then
    (cd "$1" && go tool sqlc generate) || return 1
  fi
}

# outputs <dir>: the generated files under <dir>, relative, one per line.
outputs() {
  (
    cd "$1" || exit 1
    find . -name '*.go' -type f -not -path './.git/*' -not -path './vendor/*' -print0 |
      xargs -0 grep -lE "$GENERATED" 2>/dev/null
    [ -f api/openapi.json ] && echo ./api/openapi.json
  ) | sed 's#^\./##' | sort -u
}

if [ "${1:-}" = "--write" ]; then
  regenerate . || exit 1
  echo "generated: regenerated in place; review and commit the changes"
  exit 0
fi
[ $# -eq 0 ] || { echo "usage: bash scripts/check/generated.sh [--write]" >&2; exit 2; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "generated: not a git work tree" >&2; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# The repo as it stands, tracked and new files alike, without what .gitignore leaves out.
git ls-files -z -co --exclude-standard | while IFS= read -r -d '' f; do
  [ -f "$f" ] && printf '%s\0' "$f"
done | tar --null -T - -cf - | tar -C "$tmp" -xf - || { echo "generated: could not copy the repo" >&2; exit 2; }
if ! regenerate "$tmp" >"$tmp/.generate.log" 2>&1; then
  cat "$tmp/.generate.log"
  echo "generated: a generator failed (above)" >&2
  exit 1
fi

drift=0
checked=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  checked=$((checked + 1))
  if [ ! -f "$tmp/$f" ]; then
    echo "generated: $f is committed, but no generator writes it any more; delete it"
    drift=1
  elif [ ! -f "$f" ]; then
    echo "generated: $f is generated but missing; commit it"
    drift=1
  elif ! cmp -s "$f" "$tmp/$f"; then
    echo "generated: $f differs from what its generator writes now"
    drift=1
  fi
done < <({ outputs .; outputs "$tmp"; } | sort -u)
if [ "$checked" -eq 0 ]; then
  echo "generated: no generated file found; internal/httpapi/api.gen.go should exist" >&2
  exit 1
fi
if [ "$drift" -ne 0 ]; then
  echo "Regenerate with 'bash scripts/check/generated.sh --write' and commit the result." >&2
  exit 1
fi

if has_queries .; then
  go tool sqlc vet || exit 1
  stars="$(grep -rnEi --include='*.sql' 'select[[:space:]]+(distinct[[:space:]]+)?\*|[a-z0-9_"]\.\*' db/queries)"
  if [ -n "$stars" ]; then
    printf '%s\n' "$stars"
    echo "generated: name the columns; SELECT * changes shape under a cached plan when a column is added (Rule 14)" >&2
    exit 1
  fi
else
  echo "generated: no SQL in db/queries yet, so sqlc did not run"
fi
echo "generated: $checked generated file(s) match their generators"
