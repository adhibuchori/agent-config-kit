---
paths:
  - '**/*.tsx'
  - '**/*.css'
  - 'next.config.*'
  - 'public/**'
  - '**/fonts.ts'
  - 'lighthouserc.json'
  - 'scripts/check/site.config.json'
---

# Performance: Core Web Vitals and budgets

A landing page is judged in its first seconds on a mid-range phone. Every number below is checked
by a script, so a regression shows up as a red check, not as a slow page someone notices later.

## Core Web Vitals (75th percentile of real visits)

| Metric | Good | Checked by |
| --- | --- | --- |
| LCP, Largest Contentful Paint | ≤ 2.5 s | `lighthouserc.json` (lab) |
| INP, Interaction to Next Paint | ≤ 200 ms | lab proxy: Total Blocking Time ≤ 200 ms in `lighthouserc.json` |
| CLS, Cumulative Layout Shift | ≤ 0.1 | `lighthouserc.json`; `image-budget.mjs` fails an `<img>` without dimensions |

A lab run is a proxy. The real numbers come from field data (the site's own analytics, or the
Chrome UX Report once the site has traffic); read them after launch.

## JavaScript and CSS

- Each page's first-load JavaScript and CSS (gzipped) stays under `bundle.maxJsKB` and
  `bundle.maxCssKB` in `scripts/check/site.config.json`, checked by `bundle-budget.mjs`. The
  framework's own client runtime is most of it on a small page: measure it with
  `node scripts/check/bundle-budget.mjs --report` on the first build, then set the budget to what
  you ship plus headroom.
- Server Components by default. `'use client'` only on the leaf that needs state or an event
  handler, never on a layout or a whole section.
- A heavy widget (a carousel, a map, 3D, a video player) loads with `next/dynamic` after the first
  paint, behind a placeholder of the same size. See `heavy-hero.md`.
- A third-party script loads with `next/script` and `strategy="lazyOnload"` or `afterInteractive`,
  after consent where it tracks (`analytics-consent.md`).

## Images

- Through `next/image` (the linter refuses a raw `<img>`), always with `width` and `height`, or
  `fill` inside a box that has a size. Under export, `images: { unoptimized: true }`: nothing
  resizes at request time, so the files in `public/` are what visitors download.
- `image-budget.mjs`: every raster in `public/` is under `images.maxKB` and `images.maxWidthPx`;
  a large PNG or JPEG gets an AVIF or WebP copy; and every file in `public/` is used somewhere.
  Knip does not look inside `public/`; this check does.
- The LCP image (usually the hero) gets `priority` (or `fetchPriority="high"`) and is not lazy.
  Every image below the fold stays lazy, the default.
- Size the file to the largest box it fills. A 4000 px photo in a 600 px column is the most common
  way a landing page misses LCP.

## Fonts

- At most **two families** (`fonts.maxFamilies`), self-hosted through `next/font`, which removes
  the request to a font host and sizes the fallback to limit layout shift. `font-budget.mjs` fails a
  third family or a font loaded from another host.
- Prefer a variable font over several static weights; subset to the scripts the site uses; WOFF2.
- `display: 'swap'` (the `next/font` default) so text shows at once.

## Motion

Animate `transform` and `opacity` only; layout properties (`width`, `top`, `margin`) make the
browser recompute the page every frame. Respect `prefers-reduced-motion`.
