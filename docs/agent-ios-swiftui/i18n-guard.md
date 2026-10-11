# i18n-guard

Agent · agent-ios-swiftui · `agent-ios-swiftui:i18n-guard` subagent · reads and reports only · no network

## What it does

`agent-ios-swiftui:i18n-guard` reviews a diff of an iOS app for user-facing text that skips the
String Catalog, catalog entries missing a locale or still marked new or needs review, error codes
without a translated message, package text that reads the app's bundle, and dates or numbers
formatted outside the screen's locale.

## When to reach for it

After changing a view, a screen model's text or a `Localizable.xcstrings` file:

```text
Use the agent-ios-swiftui:i18n-guard subagent on this diff.
```

**Not for:** writing or improving translations, which it only flags; have someone who speaks the
language review them instead.

## Prerequisites

- Node 20 or newer and the catalog and error-code checks that [/agent-ios-swiftui:setup](setup.md)
  installs; `scripts/check/i18n-catalog.json` lists the locales when you answered `locales=en,id`.

## Common questions

**Why does it flag `Text(name)` only sometimes?**
A `String` variable shown in `Text` is never localized. That is right for data such as a person's name or a reference code, and wrong for copy: the guard reads which one it is.

**Does a command-line build add new keys to the catalog?**
No. Only Xcode's editor syncs a catalog; add the key in the same change. The quality gate compares the catalog with the keys the build extracted.

## It's working if

- Missing locales, unfinished states and untranslated text are listed per file, with the results of
  `node scripts/check/i18n-catalog.mjs` and `bash scripts/check/error-codes.sh`.
- A clean diff gets exactly `Every string in this diff comes from the catalog, in every locale.`

## Where it fits

Next to the [reviewer](reviewer.md) of [agent-ios-swiftui](../../plugins/agent-ios-swiftui/README.md).
