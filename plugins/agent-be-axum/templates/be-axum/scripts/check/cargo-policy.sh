#!/usr/bin/env bash
# The settings every cargo call in this repo depends on, held in place (Rules 27 to 29):
#   - .cargo/config.toml sets [build] warnings = "deny" and [env] SQLX_OFFLINE = "true", and holds
#     no [source], [registries], [registry] or [net] table and no runner: those would swap where
#     crates come from or what runs the binaries, for every cargo call at once;
#   - clippy.toml is at the root (without it clippy reads one from a parent folder);
#   - rust-toolchain.toml pins an exact release, and Cargo.toml's rust-version, when set, names it;
#   - Cargo.lock is tracked, and every cargo build, check, clippy, test, nextest, llvm-cov, run,
#     doc, bench or install in gates.list, .githooks/, .github/workflows/ and a Dockerfile passes
#     --locked (or --frozen);
#   - [profile.release] sets overflow-checks = true, and no profile sets panic = "abort", which
#     would end the process where CatchPanicLayer answers 500, while every test still passes.
#
#   bash scripts/check/cargo-policy.sh
#
# Exit 1 with one line per problem.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

problems=0
problem() {
  echo "cargo-policy: $1" >&2
  problems=$((problems + 1))
}

# The lines of one TOML table ([name]), comments and blank lines left out.
table() {
  awk -v want="[$2]" '
    /^[[:space:]]*\[/ { header = $0; sub(/[[:space:]]*#.*/, "", header); gsub(/[[:space:]]/, "", header); inside = (header == want); next }
    inside && !/^[[:space:]]*(#|$)/ { print }
  ' "$1"
}

config=.cargo/config.toml
if [ ! -f "$config" ]; then
  problem "$config is missing: it carries build.warnings = \"deny\" and SQLX_OFFLINE = \"true\""
else
  table "$config" build | grep -qE '^[[:space:]]*warnings[[:space:]]*=[[:space:]]*"deny"' ||
    problem "$config: [build] must set warnings = \"deny\""
  table "$config" env | grep -qE '^[[:space:]]*SQLX_OFFLINE[[:space:]]*=[[:space:]]*("true"|\{[^}]*value[[:space:]]*=[[:space:]]*"true")' ||
    problem "$config: [env] must set SQLX_OFFLINE = \"true\""
  while IFS= read -r hit; do
    problem "$config:${hit%%:*}: no [source], [registries], [registry] or [net] table here"
  done < <(grep -nE '^[[:space:]]*\[(source|registries|registry|net)([].]|$)' "$config")
  while IFS= read -r hit; do
    problem "$config:${hit%%:*}: no runner: it would decide what runs every test and binary"
  done < <(grep -nE '^[[:space:]]*runner[[:space:]]*=' "$config")
fi

[ -f clippy.toml ] || [ -f .clippy.toml ] ||
  problem "clippy.toml is missing at the root: clippy would read one from a parent folder"

channel=""
if [ ! -f rust-toolchain.toml ]; then
  problem "rust-toolchain.toml is missing: pin the toolchain to one release"
else
  channel="$(table rust-toolchain.toml toolchain | sed -nE 's/^[[:space:]]*channel[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p')"
  [[ "$channel" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    problem "rust-toolchain.toml: channel is \"$channel\", not an exact release such as \"1.99.0\""
fi

if [ ! -f Cargo.toml ]; then
  problem "Cargo.toml is missing"
else
  rust_version="$(table Cargo.toml package | sed -nE 's/^[[:space:]]*rust-version[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p')"
  if [ -n "$rust_version" ] && [ -n "$channel" ] && [ "$rust_version" != "$channel" ] && [ "$rust_version" != "${channel%.*}" ]; then
    problem "Cargo.toml: rust-version is $rust_version but rust-toolchain.toml pins $channel; move them together"
  fi
  table Cargo.toml profile.release | grep -qE '^[[:space:]]*overflow-checks[[:space:]]*=[[:space:]]*true' ||
    problem "Cargo.toml: [profile.release] must set overflow-checks = true"
fi
for f in Cargo.toml "$config"; do
  [ -f "$f" ] || continue
  if grep -nE '^[[:space:]]*panic[[:space:]]*=[[:space:]]*"abort"' "$f" >/dev/null; then
    problem "$f: panic = \"abort\" ends the process where CatchPanicLayer would answer 500"
  fi
done

if ! git ls-files --error-unmatch Cargo.lock >/dev/null 2>&1; then
  problem "Cargo.lock is not tracked: commit it (cargo generate-lockfile makes one)"
fi

# Every cargo call that resolves dependencies, wherever this repo writes one down.
calls=()
for f in scripts/check/gates.list .githooks/* .github/workflows/*.yml .github/workflows/*.yaml Dockerfile Dockerfile.*; do
  [ -f "$f" ] && calls+=("$f")
done
if [ ${#calls[@]} -gt 0 ]; then
  while IFS= read -r hit; do
    problem "${hit%%:*}: line $(cut -d: -f2 <<<"$hit") runs cargo without --locked: ${hit#*:*:}"
  done < <(grep -nE '(^|[^[:alnum:]_-])cargo[[:space:]]+(build|check|clippy|test|nextest|llvm-cov|run|doc|bench|install)([[:space:]]|$)' "${calls[@]}" /dev/null |
    grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -vE -- '--locked|--frozen')
fi

if [ "$problems" -gt 0 ]; then
  echo "cargo-policy: $problems problem(s); see .claude/rules/backend/rust-service.md" >&2
  exit 1
fi
echo "cargo-policy: cargo config, toolchain, lockfile and release profile as the rules ask"
