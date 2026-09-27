---
description: Pre-launch checklist for a static site. Runs every gate and build check, checks legal pages, icons, 404, forms, analytics consent and preview indexing, and, given the live URL, its headers, robots, sitemap and share image; prints a pass, fail or manual table
argument-hint: "[https://live-origin]"
allowed-tools: Read, Glob, Grep, Bash(git status:*), Bash(bash scripts/check/gates.sh:*), Bash(node scripts/check/site-audit.mjs:*), Bash(node scripts/check/sitemap-robots.mjs:*), Bash(node scripts/check/bundle-budget.mjs:*), Bash(node scripts/check/a11y.mjs:*)
---

# /agent-fe-nextjs-static:launch-checklist

Live origin: `$ARGUMENTS` (optional; without it, section C is skipped and marked `MANUAL`). It reads
and reports; it changes nothing. Run it before the first launch and before any release that changes
routes, headers, forms or analytics.

Work through every item. Each gets `PASS`, `FAIL` (with the evidence and the fix) or `MANUAL` (what
a person must check, and how). The items are numbered 1 to 19 across the three sections, so the
report can cite each one by its number.

<!-- markdownlint-disable MD029 -->

## A. Automated, on this checkout

1. `bash scripts/check/gates.sh`: the source gates.
2. A fresh production build (the repo's `build` script) with the production origin set.
3. `node scripts/check/site-audit.mjs`: sitemap and robots, metadata, share images, JSON-LD, links,
   image, font and bundle budgets, the headers file with `--verify-hashes`.
4. `node scripts/check/a11y.mjs`, and `npm run check:lighthouse` when `lighthouserc.json` is
   installed. Either one exits 2 when its tool is not installed: mark it `MANUAL` with the install
   hint, not `PASS`.
5. A preview build (the build with the preview variable set) passes
   `node scripts/check/sitemap-robots.mjs --env preview`: previews stay out of search engines.

## B. Configuration and content (read the repo)

6. `siteUrl` / `NEXT_PUBLIC_SITE_URL` is the real production origin, with `https` and the chosen
   `www` form; the other form redirects to it at the host.
7. Legal pages exist and are linked from the footer on every page: privacy notice, terms, and an
   imprint or company details where the company's jurisdiction requires one. Their content is the
   owner's call: mark it `MANUAL`.
8. `not-found.tsx` exists and the built 404 page links home.
9. Icons and manifest: `app/icon.*` (or `favicon.ico`), `app/apple-icon.*`, and a `manifest` with
   name, icons and `theme_color` if the site should install or theme the browser UI.
10. Every form: the endpoint in `SSOT.md` §6 exists, validates on the server, has a honeypot and a
    rate limit that is not in memory (`.claude/rules/web/forms-on-static-hosting.md`).
11. Analytics loads only in production, only after consent where consent is needed, and its origins
    are in the CSP (`.claude/rules/web/analytics-consent.md`).
12. Old URLs (from a previous site) redirect with 301 to their new pages at the host.
13. No placeholder copy, test content or `TODO` in the built pages: search the build output for
    `lorem`, `TODO`, `example.com` (unless it is the real origin) and `<Site Name>`.

## C. On the live site (only with a live origin)

Ask before the first request: these commands reach the network. For the origin given:

```bash
ORIGIN="https://www.example.com"          # the argument, without a trailing slash
curl -sI "$ORIGIN/"                       # 200, and each header from public/_headers
curl -sI "http://${ORIGIN#https://}/"     # a redirect to https
curl -s  "$ORIGIN/robots.txt"             # production robots: allows crawling, names the sitemap
curl -sI "$ORIGIN/sitemap.xml"            # 200, an XML content type
curl -sI "$ORIGIN/opengraph-image"        # when the site uses a generated share image: image/png
curl -sI "$ORIGIN/this-page-does-not-exist"   # 404, not 200
```

With RTK installed, run each as `rtk proxy curl …`: its rewrite can reshape a response body.

14. Headers: compare each with `public/_headers` (or the host's file). A header in the file but
    missing from the response is a `FAIL`: the host does not read that file.
15. HTTPS: `http://` redirects to `https://`; HSTS is present.
16. robots and sitemap reachable, with the production origin in every URL.
17. The share image answers with an image content type
    (`.claude/anti-patterns/opengraph-image-has-no-extension-in-export.md`).
18. A wrong URL answers 404.
19. Submit each real form once from a phone and confirm the message arrives: `MANUAL`.

## Report

A table with every item, then the `FAIL` items first with their fix, then the `MANUAL` ones with
who should check them. Say plainly whether the site is ready to launch: it is only when no item is
`FAIL`.
