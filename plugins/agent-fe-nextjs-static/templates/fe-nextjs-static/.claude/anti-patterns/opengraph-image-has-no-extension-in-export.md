# A generated share image lands in `out/` without a file extension

**Applies to:** `app/**/opengraph-image.tsx` (or `twitter-image.tsx`) with `output: 'export'`
(observed on Next.js 16.3)
**Status:** Permanent while the file convention works this way

## Symptom

Link previews show no image, or a broken one, on some platforms, while the page's `og:image` tag
looks right and the file in `out/` is a valid PNG. Opening the image URL directly downloads a file
instead of showing it.

## Root cause

The export writes the generated image to `out/opengraph-image`, with no extension, and the tag
points at `https://<origin>/opengraph-image?<hash>`. A static host that picks the `Content-Type`
from the file name has nothing to pick from, and falls back to its default; nginx's stock default,
for one, is `application/octet-stream`. A link-preview crawler that trusts the header does not treat
the response as an image.

## Fix

Either:

- give the host a rule that serves `/opengraph-image` (and `/twitter-image`, and nested ones) as
  `image/png`, the `contentType` the file exports; or
- replace the generated image with a static `opengraph-image.png` next to the page, which exports
  with its extension.

## How to catch it

`node scripts/check/og-image.mjs` reads the file's bytes, so it proves the image is a PNG of the
right size, not what the host will call it. After deploy:

```bash
curl -sI "https://<origin>/opengraph-image" | grep -i '^content-type'
```

must print `image/png`.

## Scope

Export mode only; in `ssg-with-endpoints` mode Next.js serves the route with its own content type.
