# seo-validator

Agent · agent-fe-nextjs-static · `agent-fe-nextjs-static:seo-validator` subagent · reads and reports only · no network

## What it does

`agent-fe-nextjs-static:seo-validator` validates search and sharing metadata of a static site: robots
and the sitemap, canonical and hreflang links, per-route titles and descriptions, Open Graph images,
JSON-LD validity and fit, and preview indexing.

## When to reach for it

After changing public pages, metadata, robots, the sitemap, share images or structured data;
`/agent-fe-nextjs-static:seo-audit` calls it:

```text
Use the agent-fe-nextjs-static:seo-validator subagent on the changed routes.
```

**Not for:** a full audit of the built site on its own; use
[/agent-fe-nextjs-static:seo-audit](seo-audit.md) instead, which runs the checks and then calls it.

## Common questions

**What does it judge that scripts cannot?**
Whether a title describes its page, whether JSON-LD matches what the page shows, and whether a canonical choice is right.

## It's working if

- Each finding is an `[SEO] SEVERITY:` entry with the route, file, evidence and fix.
- A clean review gets exactly
  `✓ Search and sharing metadata is complete and valid for the reviewed routes.`

## Where it fits

Used by [/agent-fe-nextjs-static:seo-audit](seo-audit.md).
