---
paths:
  - '**/*.xcstrings'
  - 'App/Screens/**'
  - 'Packages/**/Sources/Features/**'
  - 'scripts/check/i18n-catalog.json'
---

# Text, String Catalogs and locale

How to follow AGENTS.md Rules 5 to 9. The rules themselves are stated once, in AGENTS.md.

## Where text comes from (Rules 5 and 8)

| Write | Not | Why |
| --- | --- | --- |
| `Text("orders.title")` | `Text(title)` with `title: String` | `Text(String)` shows the string as is, never localized |
| `let title: LocalizedStringResource` in the model, `Text(model.title)` in the view | `let title: String` | the model decides the words, the catalog their translation |
| `String(localized: "orders.title")` for UIKit | `label.text = "Orders"` | a literal assigned to UIKit is never extracted |
| `Text("orders.title", bundle: #bundle)` in a package | `Text("orders.title")` there | without a bundle the lookup reads the app's catalog |

Data is not copy: a user's name, an order number or a reference code is shown as is.

## The catalog (Rules 6 and 7)

- One `Localizable.xcstrings` per target that has text: `App/` for the app, a target's
  `Resources/` in the package. Every key has every locale the app ships
  (`scripts/check/i18n-catalog.json`), in state `translated`; `new`, `needs_review` and `stale`
  fail `scripts/check/i18n-catalog.mjs`.
- `xcodebuild` never updates a catalog; Xcode's editor does when it builds. After a change made
  outside Xcode, add the key by hand (an extracted key has no `extractionState`), or open the
  project and build once. The quality gate compares the catalog with the keys the build extracted
  and fails both ways (I4).
- A key looked up at run time, such as `problem.<CODE>`, is a manual key
  (`"extractionState" : "manual"`): no build can tell whether it is still used, so delete it with
  the code that used it.
- Keys name the place, not the words: `orders.empty`, never `"No orders yet"`.

## Numbers and dates (Rule 9)

Format in the view with a `FormatStyle`, which reads the screen's locale:

```swift
Text(order.total, format: .currency(code: "USD"))
Text(order.placedAt, format: .dateTime.day().month())
```

`value.formatted()` in a model and `String(format:)` use the process locale instead
(`.claude/anti-patterns/formatted-ignores-environment-locale.md`).
