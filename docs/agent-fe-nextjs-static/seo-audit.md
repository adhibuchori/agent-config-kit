# seo-audit

Command · agent-fe-nextjs-static · `/agent-fe-nextjs-static:seo-audit [--env preview]` · reads and reports · no network

## What it does

`/agent-fe-nextjs-static:seo-audit` checks the built site's robots, sitemap, canonical and hreflang
links, per-route titles and descriptions, share images, JSON-LD and internal links with the site
checks, then reviews what a script cannot judge. With `--env preview` it asks the opposite question:
is this preview kept out of search engines?

## When to reach for it

Before launch, after changing public pages or metadata:

```text
/agent-fe-nextjs-static:seo-audit
/agent-fe-nextjs-static:seo-audit --env preview
```

**Not for:** the live site's headers, robots and sitemap; use
[/agent-fe-nextjs-static:launch-checklist](launch-checklist.md) with the live URL instead.

## Prerequisites

- node, a build of the site (it asks you to build when there is none or it is older than the
  source) and the production origin (see below).

## Common questions

**Where does the production origin come from?**
`siteUrl` in `scripts/check/site.config.json`, or `NEXT_PUBLIC_SITE_URL`. Every absolute-URL check depends on it.

## It's working if

- `node scripts/check/site-audit.mjs --only sitemap-robots,metadata,og-image,jsonld,broken-links` exits 0.

## Where it fits

Part of [agent-fe-nextjs-static](../../plugins/agent-fe-nextjs-static/README.md), with [seo-validator](seo-validator.md).
