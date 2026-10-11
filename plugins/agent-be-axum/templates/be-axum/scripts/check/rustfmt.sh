#!/usr/bin/env bash
# The format gate: `cargo fmt --check` over the whole crate, read-only. Stable rustfmt ignores an
# unstable option in rustfmt.toml with only a warning and exit 0, so a key that silently does
# nothing fails here too.
#
#   bash scripts/check/rustfmt.sh
#
# To format instead: cargo fmt. Exit 1 when a file is not formatted or an option is ignored.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

out="$(cargo fmt --check 2>&1)"
status=$?
[ -z "$out" ] || printf '%s\n' "$out"
if grep -q 'unstable features are only available in nightly' <<<"$out"; then
  echo "rustfmt: rustfmt.toml sets an option stable rustfmt ignores; keep only options marked stable" >&2
  exit 1
fi
if [ "$status" -ne 0 ]; then
  echo "rustfmt: run cargo fmt, then commit the result" >&2
  exit 1
fi
echo "rustfmt: every file formatted"
