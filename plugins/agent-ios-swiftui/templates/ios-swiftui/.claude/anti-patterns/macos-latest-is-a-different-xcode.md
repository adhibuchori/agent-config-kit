# `macos-latest` builds with a different Xcode than yours

**Applies to:** the CI runner of the iOS quality gate (AGENTS.md Rule 19)
**Status:** Until GitHub's default macOS image ships Xcode 27

## Symptom

CI and your Mac disagree on the same commit: a warning only CI reports, a `@State` that behaves
differently, or a Swift 6.4 feature such as `@diagnose` that CI does not know.

## Root cause

GitHub's `macos-latest` is `macos-26`, whose default is Xcode 26.6 with Swift 6.3 (its runner
readme). Xcode 27 is on the `xcode-27` preview label. Two toolchains compile the same source
differently (`state-macro-changes-init-semantics.md`).

## Fix

The quality gate runs on `xcode-27` (or the repository variable `CI_RUNNER_MACOS`), selects
Xcode 27.0 through `DEVELOPER_DIR`, and fails its first step when `xcodebuild -version` prints
another build. Move your Mac and the pin together.

## How to catch it

The first lines of the gate's macOS job print the Xcode version and build.

## Scope

Every macOS job; Linux jobs run no Swift compiler.
