# Some concurrency warnings stay warnings with warnings as errors

**Applies to:** Swift 6 builds with `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` (AGENTS.md Rule 19)
**Status:** Permanent while SDK declarations use `@preconcurrency`

## Symptom

The build succeeds with warnings as errors on, yet the result bundle reports a warning, such as
`[#ActorIsolatedCall]` for a main-actor call from a nonisolated test.

## Root cause

An SDK declaration marked `@preconcurrency` downgrades the isolation error to a warning (SE-0337).
Reproduced with Swift 6.4: neither `-warnings-as-errors` nor `-Werror ActorIsolatedCall` turned it
into an error, while an ordinary unused-variable warning in the same file did fail the build.

## Fix

The warning count decides, not the exit code: `bash scripts/ios/app.sh` reads the result bundle
(`xcrun xcresulttool get build-results`) and fails on any warning, and the quality gate does the
same. Fix the warning itself; for a test that touches a view or a screen model, mark the test
`@MainActor`.

## How to catch it

`bash scripts/ios/app.sh build` prints each warning with its file and fails.

## Scope

Every build of the app target. The logic package (`swift test`) prints the same warnings in its log.
