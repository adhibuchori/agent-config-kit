# golangci-lint on one file, or with `--fast-only`, checks the wrong thing

**Applies to:** anyone running golangci-lint by hand, and hooks or scripts that lint a single edit.
**Status:** a standing trap (golangci-lint v2.14.0).

## Symptom

`golangci-lint run internal/billing/service.go` reports `typecheck` errors such as
`undefined: Store` on a file that builds fine. Or `golangci-lint run --fast-only` passes a file of
230 code lines that the full run fails.

## Root cause

- Given a file, golangci-lint type-checks that file alone, without the rest of its package, so
  every identifier from a sibling file is undefined.
- `--fast-only` runs only the fast linters (depguard, funlen, gocognit, nolintlint and a few
  more). revive is not one of them, so the 200-line file limit is not checked.
- The exclusion rules' unused warning (`Skipped 0 issues by rules`) is printed for rules aimed at
  other packages whenever a run covers only part of the module.

## Fix

- Lint a package directory with the full config: `golangci-lint run ./internal/billing/`. Format a
  single file with `golangci-lint fmt <file>`.
- The gate runs `golangci-lint run ./...` through `scripts/check/lint.sh`, which also fails on a
  stale exclusion; only a whole-module run can say a rule is stale.

## When to revisit

When golangci-lint type-checks a file within its package, or revive becomes a fast linter.
