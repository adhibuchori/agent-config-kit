# i18n-guard

Agent · agent-fe-nextjs · `agent-fe-nextjs:i18n-guard` subagent · reads and reports only · no network

## What it does

`agent-fe-nextjs:i18n-guard` validates next-intl usage in a diff: key parity between catalogues,
hardcoded user-facing strings, namespaced translators, locale-aware navigation and formatting, and
hreflang alternates.

## When to reach for it

After touching `src/messages/` or any `t()` call:

```text
Use the agent-fe-nextjs:i18n-guard subagent on this diff.
```

**Not for:** rewriting copy or translations, which it only flags; have someone who speaks the
language review them instead.

## Prerequisites

- bun and the translation checks (`bun check:i18n`) that [/agent-fe-nextjs:setup](setup.md) installs
  when you answer yes to its `i18n` question.

## Common questions

**Is it needed for a single-language app?**
No. Setup's `i18n` question installs the translation checks only for multi-language apps.

## It's working if

- Missing keys and hardcoded strings are listed per file, with the result of `bun check:i18n`.
- A clean diff gets exactly `✓ i18n keys and usage are consistent across all locales.`

## Where it fits

Works with the `localePairs` note from [post-edit](../agent-core/post-edit.md).
