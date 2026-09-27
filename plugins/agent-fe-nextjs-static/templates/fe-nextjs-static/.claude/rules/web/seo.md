---
paths:
  - '**/app/**/layout.tsx'
  - '**/app/**/page.tsx'
  - '**/app/**/page.mdx'
  - '**/app/robots.ts'
  - '**/app/sitemap.ts'
  - '**/app/manifest.ts'
  - '**/app/**/opengraph-image.*'
  - '**/app/**/twitter-image.*'
  - '**/lib/seo/**'
  - '**/lib/metadata*'
  - '**/*json-ld*'
  - '**/*structured-data*'
  - 'public/robots.txt'
  - 'public/llms.txt'
---

# Search and sharing metadata

A company site that search engines cannot read, or that indexes its own preview, loses the traffic
it exists for. What the machine can prove is proven after `next build` by
`node scripts/check/site-audit.mjs` (sitemap-robots, metadata, og-image, jsonld, broken-links); the
rest is on you in review.

## Origin

- One production origin, from `NEXT_PUBLIC_SITE_URL` (or `siteUrl` in
  `scripts/check/site.config.json`). `metadataBase` in the root layout is built from it, never from a
  request header or a hard-coded preview host.
- Every canonical, `og:url`, `og:image`, sitemap `<loc>`, hreflang href and JSON-LD URL is absolute
  on that origin. A relative or `localhost` URL is a failing check, not a style choice.

## Every indexable page

- Its own `title` (the layout's `title.template` adds the brand) and its own `description` of about
  50-160 characters. Duplicates across pages fail the metadata check.
- `alternates.canonical` pointing at itself. Point it elsewhere only for a real duplicate.
- An Open Graph image: an `opengraph-image.tsx` (or `.png`) file convention, or a static image of at
  least 1200x630, with `alt`. `twitter.card` is `summary_large_image` when an image exists.
- A page that sets its own `openGraph` replaces the inherited one whole, share image included
  (`.claude/anti-patterns/page-opengraph-drops-the-site-share-image.md`). Leave it out, and
  Next.js fills the card from the page's title and description; or build it from one helper
  that always sets `images`.
- `<html lang>` set; a page in another language sets its own.
- Do not add `keywords`: search engines ignore it, and it only goes stale.

## Languages (when the site has more than one)

- `alternates.languages` lists every language version **and** `x-default`, on every version, and
  each version lists the others back. The metadata check fails a one-way or incomplete set.
- The sitemap carries the same alternates (`alternates.languages` in `app/sitemap.ts`).

## robots and sitemap

- `app/robots.ts` and `app/sitemap.ts`, each with `export const dynamic = 'force-static'` (an export
  build fails without it). robots names the sitemap by absolute URL and blocks nothing public.
- The sitemap lists every indexable page once, and nothing that is `noindex`, redirected or missing.
  A page left out on purpose goes in `sitemapExclude`, so the choice is written down.
- A preview or staging build is never indexable: robots disallows everything, or every page sends
  `noindex`, chosen at build time from a variable the deploy pipeline sets for previews (for
  example `SITE_ENV=preview`), never from a flag someone must remember to flip. A header the host
  adds (`X-Robots-Tag: noindex`) also works; check it on the preview URL. Check a preview build with
  `node scripts/check/sitemap-robots.mjs --env preview`.

## Structured data (JSON-LD)

- Render it as the **child** of `<script type="application/ld+json">`, with `<` escaped:
  `{JSON.stringify(data).replace(/</g, '\\u003c')}`. React 19 writes a script element's text as
  is, so it stays valid JSON; `dangerouslySetInnerHTML` is refused by the linter. The jsonld check
  parses every block of the build, so a block that was HTML-escaped fails there.
- Describe only what the page shows. `Organization` (name, url, logo) on the home page,
  `BreadcrumbList` where breadcrumbs are visible, an article type on a post. The check proves the
  markup is well formed; it does not promise a rich result, and FAQ rich results are shown only for a
  few authoritative sites.

## llms.txt

`llms.txt` is a proposal (llmstxt.org), not a standard any search engine or crawler has committed to
read. Ship one only if someone asked for it; keep it to the proposal's shape (an H1, a short
blockquote, link sections) and never invent directives for it.
