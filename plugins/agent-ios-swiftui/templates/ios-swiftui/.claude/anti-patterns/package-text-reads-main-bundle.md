# Text inside a Swift package reads the app's catalog

**Applies to:** `Text`, `String(localized:)` and `LocalizedStringResource` in `Packages/**/Sources`
(AGENTS.md Rule 8)
**Status:** Permanent (documented Foundation and SwiftUI behaviour)

## Symptom

A string defined in a package target shows its key, or its English text, in every language. The
package's own `Localizable.xcstrings` has the key, translated.

## Root cause

The lookup's `bundle` defaults to the main bundle: "If `nil`, SwiftUI uses the main bundle"
(`Text.init(_:tableName:bundle:comment:)`). Code in a package target runs from the app, so the
main bundle is the app's, and the package's own catalog is never read.

## Fix

Name the package's bundle with the `#bundle` macro, which "provides the resource bundle associated
with that target":

```swift
Text("orders.empty", bundle: #bundle)
String(localized: "orders.empty", bundle: #bundle)
```

The one exception is a key that lives in the app's catalog on purpose, such as the
`problem.<CODE>` messages: say so with `bundle: .main`.

## How to catch it

SwiftLint `package_text_names_bundle` fails a literal lookup without `bundle:` in a package target.

## Scope

Every package target that has text.
