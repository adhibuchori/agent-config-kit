# seo-validator

Agent · agent-fe-nextjs · `agent-fe-nextjs:seo-validator` subagent · reads and reports only · no network

## What it does

`agent-fe-nextjs:seo-validator` validates search and sharing metadata for public routes:
`metadataBase`, per-route titles and descriptions, canonical and hreflang alternates, robots and the
sitemap, Open Graph images and JSON-LD.

## When to reach for it

After changing metadata, public pages, robots, the sitemap or share images:

```text
Use the agent-fe-nextjs:seo-validator subagent on the public routes.
```

**Not for:** a static site set up with agent-fe-nextjs-static; use
[its seo-validator](../agent-fe-nextjs-static/seo-validator.md) instead.

## Common questions

**Does it require `keywords` meta?**
No; search engines ignore it.

## It's working if

- Each finding is an `[SEO] SEVERITY:` entry with the file and the fix.
- A clean change gets exactly `✓ SEO metadata is complete and valid for the changed routes.`

## Where it fits

Part of [agent-fe-nextjs](../../plugins/agent-fe-nextjs/README.md).
