#!/usr/bin/env node
// Share cards of the built pages: every indexable page has og:title and an og:image that is an
// absolute URL on the production origin, exists in the build, is PNG/JPEG/GIF/WebP, is at least
// the configured size (1200x630 by default) and under the byte budget, and matches any declared
// og:image:width/height. Rule: .claude/rules/web/seo.md. Runs after `next build`.
//
//   node scripts/check/og-image.mjs [--dir out] [--root .] [--config scripts/check/site.config.json]
import { readFileSync, statSync } from 'node:fs';
import { relative } from 'node:path';
import {
  imageSize,
  isNoindex,
  matchesAny,
  onSite,
  openSite,
  parseHtml,
  run,
  siteUrl,
  toPosix,
  urlPath,
} from './lib/site.mjs';

const LOCAL = /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])(:\d+)?(\/|$)/i;
const SHAREABLE = new Set(['png', 'jpeg', 'gif', 'webp']);

run('og-image', ({ args, root, cfg, report }) => {
  const site = openSite(root, cfg, args.dir);
  const origin = siteUrl(cfg);
  if (!origin)
    report.error(
      'config',
      'siteUrl is not set: put the production origin in scripts/check/site.config.json or NEXT_PUBLIC_SITE_URL',
    );
  const { minWidth, minHeight, maxKB } = cfg.ogImage;
  const seen = new Map();
  let checked = 0;

  for (const page of site.pages) {
    if (page.special) continue;
    const doc = parseHtml(readFileSync(page.file, 'utf8'));
    if (isNoindex(doc) || matchesAny(page.path, cfg.sitemapExclude)) continue;
    checked++;
    const where = page.rel;
    const prop = (p) => doc.meta('property', p)[0]?.attrs.content?.trim() || '';
    const name = (n) => doc.meta('name', n)[0]?.attrs.content?.trim() || '';

    if (!prop('og:title')) report.error(where, 'no og:title');
    if (!prop('og:description'))
      report.warn(where, 'no og:description (the card falls back to the page text)');
    const image = prop('og:image') || prop('og:image:url');
    const card = name('twitter:card');
    if (!card)
      report.warn(where, 'no twitter:card (summary_large_image shows the share image full width)');

    if (!image) {
      report.error(
        where,
        'no og:image: add app/opengraph-image.* (or a static 1200x630 image) so a shared link shows a card',
      );
      continue;
    }
    if (LOCAL.test(image)) {
      report.error(
        where,
        `og:image ${image} points at localhost: set metadataBase from the production origin`,
      );
      continue;
    }
    if (!/^https?:\/\//i.test(image)) {
      report.error(
        where,
        `og:image ${image} is not an absolute URL (crawlers do not resolve relative ones)`,
      );
      continue;
    }
    if (!origin || !onSite(image, origin)) {
      if (origin)
        report.warn(
          where,
          `og:image ${image} is not on ${origin}; its size and type cannot be checked here`,
        );
      continue;
    }
    const file = site.resolvePath(urlPath(image));
    if (!file) {
      report.error(where, `og:image ${image} is not in the build`);
      continue;
    }
    if (!seen.has(file)) {
      const buf = readFileSync(file);
      seen.set(file, { size: imageSize(buf), kb: Math.ceil(statSync(file).size / 1024) });
    }
    const { size, kb } = seen.get(file);
    const rel = toPosix(relative(root, file));
    if (!size || !SHAREABLE.has(size.type)) {
      report.error(
        where,
        `og:image ${rel} is ${size ? size.type.toUpperCase() : 'not a raster image'}; share cards need PNG, JPEG, GIF or WebP`,
      );
      continue;
    }
    if (kb > maxKB) report.error(where, `og:image ${rel} is ${kb} KB (budget ${maxKB} KB)`);
    if (size.width < minWidth || size.height < minHeight) {
      report.error(
        where,
        `og:image ${rel} is ${size.width}x${size.height}; use at least ${minWidth}x${minHeight}`,
      );
    } else if (Math.abs(size.width / size.height - 1.91) > 0.19) {
      report.warn(
        where,
        `og:image ${rel} is ${size.width}x${size.height}; cards crop to about 1.91:1`,
      );
    }
    const w = prop('og:image:width');
    const h = prop('og:image:height');
    if ((w && Number(w) !== size.width) || (h && Number(h) !== size.height)) {
      report.error(
        where,
        `og:image:width/height say ${w || '?'}x${h || '?'} but ${rel} is ${size.width}x${size.height}`,
      );
    }
    if (!prop('og:image:alt')) report.warn(where, 'no og:image:alt');
  }
  return report.finish(`${checked} indexable page(s), ${seen.size} image(s)`);
});
