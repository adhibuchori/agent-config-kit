#!/usr/bin/env bash
# Coverage of the logic packages, file by file (AGENTS.md Rule 22; .claude/rules/swift/coverage.md).
# Runs every package under Packages/ with `swift test --enable-code-coverage` on the Mac (no
# simulator), exports one lcov report with `xcrun llvm-cov export -format=lcov` to
# coverage/lcov.info, and fails unless every measured file is at 100% of its lines and functions
# (scripts/check/coverage-per-file.mjs). Build folders, test files and the globs in
# scripts/check/coverage-exempt.txt are left out of the report. Xcode's xccov is never read: it
# leaves Swift package files out of its report, so a floor read from it passes at 100%.
# gates.list runs it through scripts/check/ci-env.sh, with CI's environment and nothing else.
#
#   bash scripts/check/coverage.sh
#
# Exit 0 every file at 100%, 1 a test or a file below it, 2 a missing tool or no package at all.
set -euo pipefail
cd "$(dirname "$0")/../.." || exit 2

for tool in swift xcrun node; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "coverage: $tool not found; this check runs on a Mac with Xcode and Node 20+" >&2
    exit 2
  }
done

# ci-env.sh hands this script CI's variables only, so DEVELOPER_DIR from your shell or the job does
# not reach it: the toolchain is the one xcode-select names. Say which, so a log shows it.
echo "coverage: toolchain $(xcode-select -p 2>/dev/null || echo unknown): $(swift --version 2>&1 | grep -m1 'Swift version')"

packages=()
while IFS= read -r manifest; do
  packages+=("$(dirname "$manifest")")
done < <(find Packages -mindepth 2 -maxdepth 2 -name Package.swift 2>/dev/null | sort)
[ ${#packages[@]} -gt 0 ] || {
  echo "coverage: no package under Packages/; the logic lives in Packages/AppCore (Rule 1)" >&2
  exit 2
}

exempt="$(node scripts/check/coverage-per-file.mjs ignore-regex)"
mkdir -p coverage
report=coverage/lcov.info
partial="$(mktemp "${TMPDIR:-/tmp}/lcov.XXXXXX")"
trap 'rm -f "$partial"' EXIT

for pkg in "${packages[@]}"; do
  echo "coverage: swift test --package-path $pkg --enable-code-coverage"
  swift test --package-path "$pkg" --enable-code-coverage
  codecov="$(swift test --package-path "$pkg" --show-codecov-path)"
  profdata="$(dirname "$codecov")/default.profdata"
  products="$(dirname "$(dirname "$codecov")")"
  # One test bundle per test target; llvm-cov takes the first as its binary, the rest as -object.
  binaries=()
  for bundle in "$products"/*.xctest; do
    [ -e "$bundle" ] || continue
    name="$(basename "$bundle" .xctest)"
    if [ -f "$bundle/Contents/MacOS/$name" ]; then
      binaries+=("$bundle/Contents/MacOS/$name")
    else
      binaries+=("$bundle")
    fi
  done
  [ ${#binaries[@]} -gt 0 ] || {
    echo "coverage: $pkg built no test bundle under $products" >&2
    exit 1
  }
  args=("${binaries[0]}")
  for bin in "${binaries[@]:1}"; do
    args+=(-object "$bin")
  done
  xcrun llvm-cov export -format=lcov -instr-profile "$profdata" "${args[@]}" \
    -ignore-filename-regex '/\.build/' -ignore-filename-regex '/Tests/' \
    -ignore-filename-regex "$exempt" >>"$partial"
done

mv "$partial" "$report"
trap - EXIT
node scripts/check/coverage-per-file.mjs check "$report"
