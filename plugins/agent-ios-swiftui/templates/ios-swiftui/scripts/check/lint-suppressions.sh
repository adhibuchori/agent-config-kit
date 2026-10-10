#!/usr/bin/env bash
# Every suppression says why, and the ones nothing can prove stale are not allowed at all (AGENTS.md
# Rule 17). SwiftLint parses the text after " - " in a directive as a comment and no rule of its own
# asks for one; superfluous_disable_command, at error, already fails a directive that hides nothing.
#   S1 a `swiftlint:disable…` names its rules, then " - " and a reason of 10 characters or more
#   S2 no `swiftlint:disable all`, and one .swiftlint.yml, at the root: a nested one replaces the
#      root rules for its folder without a word
#   S3 no `swift-format-ignore` comment: a path goes in .swift-format-ignore instead (a reason after
#      the directive breaks it, so it could never say why)
#   S4 no `@diagnose(<group>, as: ignored|warning …)` (SE-0522): the compiler never reports one that
#      is no longer needed, so it would outlive its reason unseen
# Reads the tracked .swift files (git ls-files), or only the files given; generated code is skipped.
#
#   bash scripts/check/lint-suppressions.sh [file.swift ...]
#
# Runs on Linux too (bash and awk only). Exit 0 clean, 1 a finding, 2 outside a git work tree.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

files=()
if [ $# -gt 0 ]; then
  files=("$@")
else
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "lint-suppressions: not a git work tree" >&2
    exit 2
  }
  while IFS= read -r f; do
    files+=("$f")
  done < <(git ls-files -- '*.swift')
fi

status=0
swift=()
for f in ${files[@]+"${files[@]}"}; do
  case "$f" in */GeneratedSources/* | */.build/*) continue ;; esac
  [ -f "$f" ] && swift+=("$f")
done
if [ ${#swift[@]} -gt 0 ]; then
  # shellcheck disable=SC2016 # an awk program: its $0 and fields are awk's, not the shell's
  out="$(awk '
    /swiftlint:disable/ {
      line = $0
      sub(/.*swiftlint:disable(:next|:this|:previous)?[ \t]*/, "", line)
      rules = line
      sub(/ - .*/, "", rules)
      reason = (index(line, " - ") > 0) ? substr(line, index(line, " - ") + 3) : ""
      gsub(/^[ \t]+|[ \t]+$/, "", reason)
      if (rules ~ /(^|[ \t])all([ \t]|$)/) {
        printf "%s:%d: S2 swiftlint:disable all switches every rule off\n", FILENAME, FNR
      } else if (length(reason) < 10) {
        printf "%s:%d: S1 swiftlint:disable without a reason after \" - \" (10 characters or more)\n", FILENAME, FNR
      }
    }
    /swift-format-ignore/ {
      printf "%s:%d: S3 swift-format-ignore: list the path in .swift-format-ignore instead\n", FILENAME, FNR
    }
    /@diagnose[ \t]*\(/ && /as:[ \t]*(ignored|warning)/ {
      printf "%s:%d: S4 @diagnose lowers or hides a diagnostic, and nothing reports it once unneeded\n", FILENAME, FNR
    }
  ' "${swift[@]}")"
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
    status=1
  fi
fi

if [ $# -eq 0 ]; then
  while IFS= read -r f; do
    [ "$f" = .swiftlint.yml ] && continue
    echo "$f: S2 a nested SwiftLint config replaces the root rules for its folder"
    status=1
  done < <(git ls-files -- '*.swiftlint.yml')
fi

if [ "$status" -eq 0 ]; then
  echo "lint-suppressions: clean (${#swift[@]} Swift file(s))"
else
  echo "lint-suppressions: suppress one rule on one line, with its reason after \" - \" (AGENTS.md Rule 17)" >&2
fi
exit "$status"
