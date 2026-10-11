# `value.formatted()` and `String(format:)` ignore the screen's locale

**Applies to:** number, date and currency formatting (AGENTS.md Rule 9)
**Status:** Permanent (documented Foundation behaviour)

## Symptom

A preview or a screen set to another locale (`.environment(\.locale, ...)`) still shows `1,250.5`
where the locale expects `1.250,5`. Nothing fails; the numbers are just wrong for the reader.

## Root cause

`Text(value, format: .number)` formats with the locale in the SwiftUI environment. `value.formatted()`
and `String(format: "%.1f", value)` run before the view exists, so they can only use the process
locale (`Locale.current`), and `"\(value)"` uses no locale at all. Reproduced with Xcode 27: under
`.environment(\.locale, Locale(identifier: "de_DE"))`, `Text(1250.5, format: .number)` rendered
`1.250,5` and `Text(value.formatted())` rendered `1,250.5`.

## Fix

Keep the value a number until the view, and format it there:

```swift
Text(order.total, format: .currency(code: "USD"))   // the screen's locale
```

A screen model that must build a sentence takes the locale as a parameter.

## How to catch it

SwiftLint `no_unlocalized_format` fails `String(format:)` without `locale:`; the reviewer reads
`.formatted()` in screen models.

## Scope

Every displayed number and date.
