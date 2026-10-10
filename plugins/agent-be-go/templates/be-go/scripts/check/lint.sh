#!/usr/bin/env bash
# Lint gate: golangci-lint over the whole module with .golangci.yml, at the version
# scripts/check/tools.env pins. Fails on any finding, on another golangci-lint version, and on an
# exclusion rule that no longer excludes anything (golangci-lint only warns "Skipped 0 issues by
# rules"; a stale exclusion is a hole waiting for the next finding).
#
#   bash scripts/check/lint.sh
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2
# Nothing downloads a toolchain, and go.mod and go.sum are never rewritten.
export GOTOOLCHAIN=local GOFLAGS=-mod=readonly

want="$(sed -n 's/^GOLANGCI_LINT_VERSION=//p' scripts/check/tools.env)"
[ -n "$want" ] || { echo "lint: scripts/check/tools.env has no GOLANGCI_LINT_VERSION" >&2; exit 2; }
if ! command -v golangci-lint >/dev/null 2>&1; then
  echo "lint: golangci-lint is not installed; install release v$want (the binary from its GitHub release, checked against its checksums file)" >&2
  exit 1
fi
have="$(golangci-lint version --short 2>/dev/null)"
if [ "${have#v}" != "$want" ]; then
  echo "lint: golangci-lint ${have:-of unknown version} found; this repo pins v$want (scripts/check/tools.env)" >&2
  exit 1
fi

log="$(mktemp)"
trap 'rm -f "$log"' EXIT
golangci-lint run ./... >"$log" 2>&1
status=$?
cat "$log"
if grep -q 'Skipped 0 issues by rules' "$log"; then
  echo "lint: an exclusion rule in .golangci.yml excludes nothing any more; delete it" >&2
  exit 1
fi
exit "$status"
