# `swiftlint analyze` passes because it analyzed nothing

**Applies to:** SwiftLint analyzer rules (`unused_import`, `unused_declaration`) with Xcode 26 or later
**Status:** Upstream bug (SwiftLint issue #6877, open in August 2026); delete this file once a
release fixes it

## Symptom

`swiftlint analyze --compiler-log-path xcodebuild.log` after a clean build prints "Found 0
violations, 0 serious in 0 files" and exits 0. A seeded unused declaration is not reported.

## Root cause

Xcode 26 and later pass the compiler's arguments in `@response` files, which SwiftLint's
compiler-log parser does not expand, so it finds no file to analyze. Zero files is reported as
success.

## Fix

Dead code goes to Periphery (`periphery scan --strict`), which reads Xcode's index store and fails
on what it finds (AGENTS.md Rule 27); the quality gate runs it. The analyzer rules stay out of
`.swiftlint.yml`. An unused import has no working tool today: the reviewer reads imports.

## How to catch it

Any check that reports a count of files: "0 files" is a failure, not a pass.

## Scope

Every Xcode 26+ toolchain until a SwiftLint release expands response files.
