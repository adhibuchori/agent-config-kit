# `Text(someString)` is never localized

**Applies to:** every SwiftUI `Text` built from a `String` value (AGENTS.md Rule 5)
**Status:** Permanent (documented SwiftUI behaviour)

## Symptom

A screen shows English in every language, although the key is in the String Catalog with every
locale translated. The gates pass: the catalog is complete, and no lint rule fired.

## Root cause

`Text` has two initializers that look alike. `Text("orders.title")` takes a `LocalizedStringKey`
and looks it up. `Text(title)` with `title: String` "displays the string without localization"
(Apple's `Text.init(_:)` for `StringProtocol`). The compiler picks the second whenever the argument
is a `String` variable, so a model that exposes `var title: String` turns every screen that shows
it into untranslated text. SwiftLint sees text, not types, so no rule can tell the two apart.

## Fix

The model exposes `LocalizedStringResource`, and the view passes it on:

```swift
package var title: LocalizedStringResource { "orders.title" }   // in the screen model
Text(model.title)                                                // in the view
```

Data is not copy: a name or a reference code is shown with `Text(value)` on purpose.

## How to catch it

The reviewer and the `i18n-guard` subagent read every `Text(` whose argument is not a literal. The
quality gate's I4 check finds the key the code never extracts.

## Scope

Every view. Revisit if SwiftUI ever stops accepting `StringProtocol` in `Text`.
