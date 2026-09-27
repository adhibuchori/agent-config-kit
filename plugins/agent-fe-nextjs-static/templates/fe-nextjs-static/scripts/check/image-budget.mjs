#!/usr/bin/env node
// Images and other public/ assets. Always: every raster in public/ is under the byte budget and the
// width cap, large PNG/JPEG/GIF files are flagged for AVIF/WebP, and every file in public/ is used
// somewhere (Knip cannot see public/). With a build (--dir, or the mode's output folder when it
// exists): every <img> carries width and height so it cannot shift the layout, and references
// from the built files count as uses. --source-only ignores any build (the pre-commit mode).
// Rule: .claude/rules/web/performance.md. Budgets: images.* in scripts/check/site.config.json.
//
//   node scripts/check/image-budget.mjs [--source-only] [--dir out] [--root .] [--config FILE]
import { existsSync, readFileSync, statSync } from 'node:fs';
import { basename, join, relative } from 'node:path';
import {
  UsageError,
  filesUnder,
  imageSize,
  matchesAny,
  openSite,
  parseHtml,
  run,
  sourceFiles,
  toPosix,
} from './lib/site.mjs';

const RASTER = /\.(png|jpe?g|gif|webp|avif)$/i;
const LEGACY = /\.(png|jpe?g|gif)$/i;
const TEXT = /\.(html?|css|js|mjs|json|txt|xml|webmanifest|svg|body|rsc)$/i;
// Served by convention, never referenced from a page.
const CONVENTIONAL = [
  'favicon.ico',
  'robots.txt',
  'sitemap.xml',
  'manifest.webmanifest',
  'site.webmanifest',
  'manifest.json',
  '_headers',
  '_redirects',
  'humans.txt',
  'llms.txt',
  'llms-full.txt',
  'ads.txt',
  'app-ads.txt',
  'browserconfig.xml',
  'CNAME',
  '.nojekyll',
  '404.html',
  'apple-touch-icon*.png',
  '.well-known/**',
];

run(
  'image-budget',
  ({ args, root, cfg, report }) => {
    const { maxKB, maxWidthPx, modernFormatKB, unusedIgnore } = cfg.images;
    const publicDir = join(root, 'public');
    const assets = filesUnder(publicDir).filter((f) => basename(f) !== '.DS_Store');

    for (const f of assets.filter((a) => RASTER.test(a))) {
      const rel = toPosix(relative(root, f));
      const kb = Math.ceil(statSync(f).size / 1024);
      if (kb > maxKB)
        report.error(rel, `${kb} KB is over the ${maxKB} KB image budget: resize or re-encode it`);
      else if (LEGACY.test(f) && kb > modernFormatKB)
        report.warn(
          rel,
          `${kb} KB ${f.split('.').pop().toUpperCase()}: an AVIF or WebP copy is usually far smaller`,
        );
      const size = imageSize(readFileSync(f));
      if (size && size.width > maxWidthPx)
        report.error(
          rel,
          `${size.width}px wide; nothing on a page needs more than ${maxWidthPx}px`,
        );
    }

    // Where to look for references: the build when there is one, and always the source.
    let site = null;
    if (!args['source-only']) {
      try {
        site = openSite(root, cfg, args.dir);
      } catch (e) {
        if (!(e instanceof UsageError) || args.dir) throw e;
      }
    }
    const haystack = [];
    const addText = (f) => {
      try {
        haystack.push(readFileSync(f, 'utf8'));
      } catch {
        // unreadable: skip
      }
    };
    sourceFiles(root).forEach(addText);
    if (site) {
      const buildRoots =
        site.mode === 'export' || args.dir || cfg.outDir
          ? [site.pagesDir]
          : [site.pagesDir, join(root, '.next/static')];
      for (const r of buildRoots)
        filesUnder(r)
          .filter((f) => TEXT.test(f))
          .forEach(addText);
    }
    for (const extra of [
      'public/manifest.webmanifest',
      'public/site.webmanifest',
      'public/_headers',
    ]) {
      if (existsSync(join(root, extra))) addText(join(root, extra));
    }
    const text = haystack.join('\n');

    let unused = 0;
    for (const f of assets) {
      const rel = toPosix(relative(publicDir, f));
      if (matchesAny(rel, CONVENTIONAL) || matchesAny(rel, unusedIgnore)) continue;
      const encoded = rel.split('/').map(encodeURIComponent).join('/');
      if (text.includes(rel) || text.includes(encoded) || text.includes(basename(f))) continue;
      unused++;
      report.error(
        `public/${rel}`,
        'is not referenced by the source or the build: delete it, or list it in images.unusedIgnore if a URL is built at run time',
      );
    }

    let imgs = 0;
    if (site) {
      for (const page of site.pages) {
        const doc = parseHtml(readFileSync(page.file, 'utf8'));
        for (const img of doc.all('img')) {
          imgs++;
          const a = img.attrs;
          const style = (a.style || '').replace(/\s+/g, '');
          const sized =
            (a.width && a.height) ||
            a['data-nimg'] === 'fill' ||
            (/(^|;)width:/.test(style) && /(^|;)height:/.test(style)) ||
            /aspect-ratio:/.test(style);
          if (!sized)
            report.error(
              `${page.rel} <img src="${a.src || ''}">`,
              'has no width and height: the page shifts when it loads (use next/image, or set both)',
            );
        }
      }
    } else {
      report.info(
        `${args['source-only'] ? 'source only' : 'no build found'}: <img> dimensions not checked (run after next build, or pass --dir)`,
      );
    }
    return report.finish(
      `${assets.length} public file(s), ${unused} unused, ${imgs} <img> in the build`,
    );
  },
  { switches: ['source-only'] },
);
