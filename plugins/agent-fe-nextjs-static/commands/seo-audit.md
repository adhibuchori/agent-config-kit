---
description: SEO audit of the built site. Checks robots, the sitemap, canonical and hreflang links, per-route titles and descriptions, share images, JSON-LD and internal links with the site checks, then reviews what they cannot judge; reports without changing anything
argument-hint: "[--env preview]"
allowed-tools: Read, Glob, Grep, Bash(git status:*), Bash(git diff:*), Bash(node scripts/check/site-audit.mjs:*), Bash(node scripts/check/sitemap-robots.mjs:*), Bash(node scripts/check/metadata.mjs:*), Bash(node scripts/check/og-image.mjs:*), Bash(node scripts/check/jsonld.mjs:*), Bash(node scripts/check/broken-links.mjs:*)
---

# /agent-fe-nextjs-static:seo-audit

Arguments: `$ARGUMENTS`. With `--env preview`, the audit asks the opposite question: is this preview
build kept out of search engines? It reads and reports; fixing is a separate request.

## 1. The build and the origin

The checks read built pages. Find the build (`out/` in export mode, `.next/server/app/`
otherwise); if there is none or it is older than the source, ask the user to build, or build if
they agree. The production origin comes from `siteUrl` in `scripts/check/site.config.json` or from
`NEXT_PUBLIC_SITE_URL`; if neither is set, say so first: every absolute-URL check depends on it.

## 2. The checks

```bash
node scripts/check/site-audit.mjs --only sitemap-robots,metadata,og-image,jsonld,broken-links
```

With `--env preview`, run instead:

```bash
node scripts/check/sitemap-robots.mjs --env preview
```

Report each check's exit code (0 clean, 1 findings, 2 could not run) and quote its `ERROR` and
`WARN` lines. Each check's header in `scripts/check/` says exactly what it proves.

## 3. What the checks cannot judge

Use the `agent-fe-nextjs-static:seo-validator` subagent on the changed routes (or on every route,
for a full audit), and read its report. It covers what a script cannot:

- whether each title and description describes its page, reads well, and differs from its
  neighbours in more than a word;
- whether JSON-LD matches what the page visibly shows;
- whether the canonical choice is right for a page that is a real duplicate;
- whether the preview-noindex switch is wired to the deploy environment rather than a hand flag;
- `llms.txt`, if the site ships one: it is a proposal, not a standard, and nothing requires it.

## 4. Report

```text
[SEO] SEVERITY: what is wrong
  Route: /about   File: app/about/page.tsx
  Evidence: <the check's line, or what you read>
  Fix: ...
```

Severity: `CRITICAL` (the site or a page cannot be indexed, or a private or preview page can be) ·
`HIGH` (wrong canonical, broken hreflang set, missing share image) · `MEDIUM` · `LOW`. Close with the
checks' table from step 2, so the reader sees what passed.
