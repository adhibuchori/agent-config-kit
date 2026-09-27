---
paths:
  - 'next.config.*'
  - 'middleware.ts'
  - 'proxy.ts'
  - 'src/middleware.ts'
  - 'src/proxy.ts'
  - '**/app/**/route.ts'
  - '**/app/**/page.tsx'
  - '**/app/**/layout.tsx'
  - '**/actions.ts'
  - '**/*.action.ts'
  - 'scripts/check/site.config.json'
---

# Keep the site static

Every page is HTML made at build time. The site has one of two shapes, set by `mode` in
`scripts/check/site.config.json` (`auto` reads `next.config`):

| Mode | next.config | Endpoints |
| --- | --- | --- |
| `export` | `output: 'export'`; `next build` writes `out/`, which any static host serves | none in this app: a form posts to a separate endpoint |
| `ssg-with-endpoints` | no `output: 'export'`; the host runs Next.js | route handlers only under the `endpoints` globs (default `app/api/**`) |

`node scripts/check/static-export.mjs` enforces this from the source, in pre-commit.

## Export mode: what the build does not tell you

`next build` fails loudly for some of these and **passes silently** for others. The silent ones are
the dangerous ones: the site deploys, and a header, a redirect or a form simply is not there.

| You write | What happens under `output: 'export'` | Do instead |
| --- | --- | --- |
| `headers()`, `redirects()`, `rewrites()` in next.config | ignored; the build only prints a warning | the host's config: `public/_headers` or its redirect file |
| `proxy.ts` / `middleware.ts` | builds, never runs | build-time work, or the host's config |
| a route handler with `POST` (or any non-GET) | builds; `out/` has no such file | a separate endpoint (see `forms-on-static-hosting.md`) |
| `app/robots.ts`, `app/sitemap.ts`, `opengraph-image.tsx` without `export const dynamic = 'force-static'` | build fails | add the export |
| a `[slug]` segment without `generateStaticParams` | build fails | return every slug from `generateStaticParams` in the page or a layout at or below the segment |
| `'use server'` actions, `cookies()`, `headers()`, `draftMode()`, `searchParams` in a server page, `force-dynamic`, `revalidate = N`, `dynamicParams = true` | build fails or the feature does nothing | move the request-time part to a client component or an endpoint; rebuild to update content |
| `next/image` with the default loader | build fails | `images: { unoptimized: true }` and size the files yourself, or a custom `loader` |

Also: a `not-found.tsx` in the app root, so a wrong URL gets the site's own 404 page (`404.html`).

## ssg-with-endpoints mode

- Pages still prerender: no `force-dynamic`, no request-time API, no dynamic segment without
  `generateStaticParams` outside the endpoint folders.
- Route handlers, server actions and `next/headers` live only under `endpoints`. One job each (a
  contact form, a newsletter sign-up), validated on the server.
- A `proxy.ts` / `middleware.ts` runs on every request: keep it to locale routing or headers, never
  page data.

## Content changes

Content is part of the build. Updating copy means a commit and a rebuild, not ISR or a runtime
fetch. A CMS, if any, is read at build time.
