# i18n-guard

Agent · agent-fe-nextjs-static · `agent-fe-nextjs-static:i18n-guard` subagent · reads and reports only · no network

## What it does

`agent-fe-nextjs-static:i18n-guard` validates next-intl on a static site: locale routing that works
without middleware (`app/[locale]` with `generateStaticParams` and `setRequestLocale`), catalogue key
parity, hardcoded strings, locale-aware formatting and reciprocal hreflang alternates.

## When to reach for it

After touching message catalogues, locale routing or localized metadata. Optional:

```text
Use the agent-fe-nextjs-static:i18n-guard subagent on this diff.
```

**Not for:** a site that does not use next-intl, where it says so and stops; use
[seo-validator](seo-validator.md) for its hreflang links instead.

## Common questions

**Why no middleware?**
Middleware does not run on a static export; locale routing must be static.

## It's working if

- Each finding is an `[I18N]` entry with the key, the file and the fix.
- A clean diff gets exactly `✓ i18n routing, keys and usage are consistent across all locales.`

## Where it fits

Optional part of [agent-fe-nextjs-static](../../plugins/agent-fe-nextjs-static/README.md).
