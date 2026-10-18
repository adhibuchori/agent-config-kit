# A string literal in a ternary or a tuple is not extracted

**Applies to:** `Localizable.xcstrings`, the I4 check (AGENTS.md Rules 6 and 7)
**Status:** Permanent (Xcode 27's string extraction)

## Symptom

The gate's String Catalog check reports `I4 "<key>" was extracted from code, yet no code uses it
now` for a key the code still uses, such as `"bills.add.subtitle"` in
`subtitle: isEditing ? "bills.edit.subtitle \(name)" : "bills.add.subtitle"`, or
`case .whatsApp: ("guide.action.whatsApp", .chat)`.

## Root cause

The compiler writes a key to `.stringsdata` only where the literal is typed as localizable at the
point it appears. A literal in one branch of a ternary, or in a tuple whose type is inferred later,
is typed after extraction ran, so the build never lists it. The app still shows the translation at
run time.

## Fix

Mark the entry manual in the catalog, by hand and in its sorted place:

```json
"bills.add.subtitle" : {
  "extractionState" : "manual",
  "localizations" : { ... }
}
```

The check then counts the key as looked up by name (I5). Or give the literal its type where it is
written (`LocalizedStringResource("bills.add.subtitle")`) so the build extracts it.

## How to catch it

`node scripts/check/i18n-catalog.mjs --stringsdata .build/xcode` after a build; grep the key in the
code before deleting an entry I4 calls unused.

## Scope

Every key written inside a conditional expression or a tuple.
