# Anti-Patterns Index

> Lazy-loaded knowledge base. Load only the file(s) matching your current task.
> Each file is self-contained: symptom, root cause, fix and scope.

## Loading Guide

| Trigger / Task | Load |
| --- | --- |
| Showing a `String` in `Text`, or a model property that holds display text | text-string-is-never-localized.md |
| Adding text to a Swift package target, or a package string shows untranslated | package-text-reads-main-bundle.md |
| Formatting a number, date or currency outside a view | formatted-ignores-environment-locale.md |
| The backend added an error code, or a response with an unknown code fails to decode | closed-openapi-enum-throws-on-new-code.md |
| Reaching for `swiftlint analyze`, `unused_import` or `unused_declaration` | swiftlint-analyze-sees-zero-files.md |
| A file "over 150 lines" by `wc -l` that SwiftLint passes, or the reverse | file-length-counts-comments-by-default.md |
| A `.swiftlint.yml` below the root, or a folder that ignores the root rules | nested-swiftlint-config-replaces-root.md |
| A `@State` initial value with a side effect, or behaviour that differs between Xcode versions | state-macro-changes-init-semantics.md |
| A warning left in a build that treats warnings as errors | preconcurrency-warnings-escape-werror.md |
| Reading coverage from Xcode or an `.xcresult` | xccov-omits-package-files.md |
| A key used in code is missing from `Localizable.xcstrings` after a command-line build | xcodebuild-never-syncs-string-catalog.md |
| Picking a CI runner, or CI compiles differently from your Mac | macos-latest-is-a-different-xcode.md |
| The gate's macOS job times out, or audit tests fail in CI only | full-accessibility-audit-outlasts-hosted-runner.md |
| Periphery names a line the file no longer has | periphery-reads-a-stale-index.md |
| I4 calls a key unused that the code still uses | string-literal-in-ternary-is-not-extracted.md |

## When to add a new entry

A new anti-pattern qualifies when:

- It cost real debugging time (more than 30 minutes)
- The root cause is not obvious from reading the code or the docs
- The same trap is likely to come back (a vendor bug, an environment quirk, a tool's default)

If the bug gets fixed upstream, **delete the file**: do not leave stale entries.

## File naming convention

`<scope>-<short-description>.md`: kebab-case, descriptive enough to skip without opening.
