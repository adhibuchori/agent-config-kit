# `xcodebuild` never updates the String Catalog

**Applies to:** `Localizable.xcstrings` (AGENTS.md Rules 6 and 7)
**Status:** Permanent (Xcode 27's build system)

## Symptom

A new `Text("orders.empty")` builds and runs from the command line, and the catalog has no
`orders.empty` key: the screen shows the key itself in every language. A green build says nothing
about translations either: the compiled catalog ships values still marked `new` or `needs_review`.

## Root cause

Xcode's editor syncs the catalog each time it builds; `xcodebuild` only compiles it
(`XCStrings.xcspec` runs `xcstringstool compile`). With `SWIFT_EMIT_LOC_STRINGS = YES` the
compiler writes one `.stringsdata` file per Swift file with the keys it extracted, and nothing
reads them back into the catalog. Observed with Xcode 27.0: `git status` stayed clean after a
command-line build that added a key.

## Fix

- Add the key to the catalog in the same change, with every locale (by hand, or by building once
  in Xcode).
- `node scripts/check/i18n-catalog.mjs` checks locales and states on every commit (I1, I2, I3). The
  quality gate's macOS job passes it the build's `.stringsdata` (`--stringsdata`), and it fails a key
  the code uses that the catalog lacks, and an extracted key no code uses (I4).

## How to catch it

`node scripts/check/i18n-catalog.mjs --stringsdata .build/xcode` after `bash scripts/ios/app.sh build`.

## Scope

Every catalog an agent or a script edits outside Xcode.
