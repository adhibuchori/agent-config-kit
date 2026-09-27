# seo-validator

Agent · agent-docs-nextra · `agent-docs-nextra:seo-validator` subagent · reads and reports only · no network

## What it does

`agent-docs-nextra:seo-validator` reviews a docs-site change for page metadata, the heading outline,
and the favicon, robots and sitemap files a static export serves.

## When to reach for it

When a change touches `app/layout.tsx` metadata, content pages or public files:

```text
Use the agent-docs-nextra:seo-validator subagent on this diff.
```

**Not for:** security headers or secrets in the export; use
[agent-docs-nextra:security-guard](security-guard.md) instead.

## Common questions

**Does it edit pages?**
No. It reports; you or Claude fix in a separate step.

## It's working if

- Each finding is an `[SEO] SEVERITY:` entry with the file and the fix.
- A clean change gets `SEO setup is complete and valid for the current baseline.`

## Where it fits

Part of [agent-docs-nextra](../../plugins/agent-docs-nextra/README.md).
