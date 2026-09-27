#!/usr/bin/env bash
# Prints the lines a branch adds under the pathspecs that match an extended regex, as path:line: text.
# Usage: diff-scan.sh <base-ref> <extended-regex> <pathspec>...
# Exit 0 no match, 1 a match, 2 the diff could not be read or the pattern could not run.
#
# Only added lines count: a line the branch removes, or a header line of the diff, never matches.
# awk reads the whole diff, so git never dies of SIGPIPE on a large one.
set -uo pipefail

if [ $# -lt 3 ]; then
  echo "usage: diff-scan.sh <base-ref> <extended-regex> <pathspec>..." >&2
  exit 2
fi
base=$1
re=$2
shift 2

work=$(mktemp -d) || exit 2
trap 'rm -rf "$work"' EXIT

# Each added line becomes path TAB line TAB text. Header lines sit between "diff --git" and the first
# "@@", so an added line whose own text starts with "+++" is still read as content.
if ! git -c core.quotePath=false diff --unified=0 --no-color --no-ext-diff --no-textconv \
  --src-prefix=a/ --dst-prefix=b/ "${base}...HEAD" -- "$@" | awk '
  /^diff --git / { hdr = 1; next }
  hdr && /^\+\+\+ / { path = substr($0, 5); sub(/^b\//, "", path); next }
  /^@@ / { hdr = 0; split($3, n, ","); line = substr(n[1], 2) + 0; next }
  hdr { next }
  /^\+/ { printf "%s\t%d\t%s\n", path, line, substr($0, 2); line++ }
' >"$work/added"; then
  echo "diff-scan: could not read the diff between $base and HEAD" >&2
  exit 2
fi

# The regex sees only the text column, never the path; -a keeps a stray binary byte from hiding lines.
tab=$(printf '\t')
grep -aE "^[^${tab}]*${tab}[^${tab}]*${tab}.*(${re})" "$work/added" >"$work/hits"
case $? in
0) ;;
1) exit 0 ;;
*)
  echo "diff-scan: grep could not run the pattern: $re" >&2
  exit 2
  ;;
esac

awk -F '\t' '
  NR <= 20 { t = $0; sub(/^[^\t]*\t[^\t]*\t/, "", t); printf "%s:%s: %s\n", $1, $2, t }
  END { if (NR > 20) printf "... and %d more\n", NR - 20 }
' "$work/hits"
exit 1
