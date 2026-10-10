# A nested `.swiftlint.yml` silently replaces the root rules for its folder

**Applies to:** SwiftLint configuration and suppressions (AGENTS.md Rule 17)
**Status:** Permanent (SwiftLint's documented nested configurations)

## Symptom

Code in one folder breaks rules the gate enforces everywhere else, and `swiftlint lint` passes.
Someone added a `.swiftlint.yml` there, often copied from another project.

## Root cause

SwiftLint applies a configuration file it finds below the root to that folder ("Nested
Configurations" in its README). Observed with 0.65: a stray `Packages/AppCore/.swiftlint.yml`
replaced the root rules for the whole package, with no message.

Three other ways to switch a check off leave no trace either:

- `// swiftlint:disable all`, or a rule disabled to the end of the file;
- `// swift-format-ignore: Rule - reason`: the reason is read as part of the rule list, so the
  directive breaks and the finding comes back, which teaches people to drop the reason;
- Swift 6.4's `@diagnose(<group>, as: ignored)`, which hides a warning even with warnings as errors,
  and is never reported once it is no longer needed.

## Fix

One `.swiftlint.yml`, at the root. A suppression covers one rule on one line and says why:

```swift
// swiftlint:disable:next force_cast - the SDK boxes this value as Int
```

A path swift-format skips goes in `.swift-format-ignore`.

## How to catch it

`scripts/check/lint-suppressions.sh` fails a nested config (S2), a disable without a reason (S1), an
inline `swift-format-ignore` (S3) and a lowering `@diagnose` (S4); SwiftLint's
`superfluous_disable_command` fails a disable that hides nothing.

## Scope

Every folder SwiftLint reads.
