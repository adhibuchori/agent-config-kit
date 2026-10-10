# Xcode's coverage report leaves Swift package files out

**Applies to:** coverage of `Packages/AppCore` (AGENTS.md Rule 22)
**Status:** Observed with Xcode 27.0 (no upstream report found); check again with a new Xcode

## Symptom

A coverage floor read from Xcode passes at 100% while most of the package's code has no test.

## Root cause

Reproduced with Xcode 27.0. `xcrun xccov view --report` on an `xcodebuild test` of the package
scheme listed the package target with 0 of 0 lines and no files, and reported the test file
alone: 100%. Through the app scheme, the app's files appeared and the package's did not. Reading the
same profile with `llvm-cov` showed the true figure: 52.6% of lines.

## Fix

Measure the package with SwiftPM and llvm-cov, as `scripts/check/coverage.sh` does:

```bash
swift test --package-path Packages/AppCore --enable-code-coverage
xcrun llvm-cov export -format=lcov -instr-profile <codecov>/default.profdata <test bundle binary> > coverage/lcov.info
```

`scripts/check/coverage-per-file.mjs` then checks each file at 100% of its lines and functions.

## How to catch it

A file you know is untested must appear in the report at less than 100%; if it is missing, the
report is wrong.

## Scope

Every Swift package measured through Xcode.
