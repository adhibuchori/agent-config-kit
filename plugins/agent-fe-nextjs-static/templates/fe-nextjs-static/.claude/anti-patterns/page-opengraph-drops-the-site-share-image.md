# A page's own `openGraph` drops the site's share image

**Applies to:** `app/opengraph-image.*` (or a layout's `openGraph.images`) with pages that set
`openGraph` in their metadata (observed on Next.js 16.3)
**Status:** Permanent (documented metadata merging: a nested object is replaced, not merged)

## Symptom

The home page shows a share card with the image; every other page shows a card without one, or no
large card at all. The pages' `og:title` and `og:description` are right, which is why nobody
notices until a link is shared.

## Root cause

Metadata from a layout and a page is merged one level deep. When a page sets `openGraph`, its object
**replaces** the inherited one whole, and the share image that `app/opengraph-image.tsx` (or the
layout) put there goes with it. The home page keeps the image only because the image file sits in
the same segment.

A page that sets no `openGraph` at all keeps the inherited image, and Next.js fills `og:title` and
`og:description` from the page's `title` and `description`.

## Fix

Either:

- leave `openGraph` out of the page's metadata, and let the page's `title` and `description` flow
  into the card; or
- when a page needs its own `openGraph` (an article type, a page-specific image), build it from one
  shared helper that always sets `images`, for example `images: '/opengraph-image'`.

## How to catch it

`node scripts/check/og-image.mjs` after `next build` fails every indexable page without an
`og:image`, and names it.

## Scope

Every nested metadata object behaves this way (`openGraph`, `twitter`, `robots`, `alternates`):
set one on a page, and you set all of it.
