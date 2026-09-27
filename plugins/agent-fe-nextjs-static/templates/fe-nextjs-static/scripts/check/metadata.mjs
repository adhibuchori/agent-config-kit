#!/usr/bin/env node
// Per-route metadata of the built pages: <html lang>, viewport, a unique title and description,
// an absolute self-canonical on the production origin, and reciprocal hreflang alternates with
// x-default. Rule: .claude/rules/web/seo.md. Runs after `next build`.
//
//   node scripts/check/metadata.mjs [--dir out] [--root .] [--config scripts/check/site.config.json]
import { readFileSync } from 'node:fs';
import {
  isNoindex,
  matchesAny,
  normUrl,
  onSite,
  openSite,
  parseHtml,
  run,
  siteUrl,
  urlPath,
} from './lib/site.mjs';

const LOCAL = /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])(:\d+)?(\/|$)/i;
const HREFLANG = /^(x-default|[a-z]{2,3}(-[A-Za-z]{4})?(-([A-Za-z]{2}|[0-9]{3}))?)$/;

run('metadata', ({ args, root, cfg, report }) => {
  const site = openSite(root, cfg, args.dir);
  const origin = siteUrl(cfg);
  if (!origin)
    report.error(
      'config',
      'siteUrl is not set: put the production origin in scripts/check/site.config.json or NEXT_PUBLIC_SITE_URL',
    );

  const docs = new Map();
  const readDoc = (file) => {
    if (!docs.has(file)) docs.set(file, parseHtml(readFileSync(file, 'utf8')));
    return docs.get(file);
  };

  const titles = new Map();
  const descriptions = new Map();
  let checked = 0;

  for (const page of site.pages) {
    if (page.special) continue;
    const doc = readDoc(page.file);
    const where = page.rel;
    checked++;

    const html = doc.all('html')[0];
    if (!html || !(html.attrs.lang || '').trim())
      report.error(where, '<html> has no lang attribute');
    if (!doc.meta('name', 'viewport').length) report.error(where, 'no <meta name="viewport">');

    if (isNoindex(doc) || matchesAny(page.path, cfg.sitemapExclude)) continue;

    const titleTags = doc.all('title');
    const title = (titleTags[0]?.text || '').trim();
    if (!title) report.error(where, 'no <title>, or an empty one');
    else if (titleTags.length > 1) report.error(where, `${titleTags.length} <title> elements`);
    else titles.set(title, [...(titles.get(title) || []), page.path]);

    const descTags = doc.meta('name', 'description');
    const desc = (descTags[0]?.attrs.content || '').trim();
    if (!desc) report.error(where, 'no <meta name="description">, or an empty one');
    else {
      if (descTags.length > 1) report.error(where, `${descTags.length} description meta tags`);
      descriptions.set(desc, [...(descriptions.get(desc) || []), page.path]);
      const { minChars, maxChars } = cfg.description;
      if (desc.length < minChars || desc.length > maxChars) {
        report.warn(
          where,
          `description is ${desc.length} characters; aim for ${minChars}-${maxChars} so it is not cut or padded in results`,
        );
      }
    }

    const canonicals = doc.links('canonical');
    const canonical = canonicals[0]?.attrs.href || '';
    if (!canonical) report.error(where, 'no <link rel="canonical">');
    else if (canonicals.length > 1) report.error(where, `${canonicals.length} canonical links`);
    else if (LOCAL.test(canonical))
      report.error(
        where,
        `canonical ${canonical} points at localhost: set metadataBase from the production origin`,
      );
    else if (!/^https?:\/\//i.test(canonical))
      report.error(where, `canonical ${canonical} is not an absolute URL`);
    else if (origin && !onSite(canonical, origin))
      report.error(where, `canonical ${canonical} is not on ${origin}`);
    else if (origin) {
      const target = urlPath(canonical);
      if (!site.resolvePath(target))
        report.error(where, `canonical ${canonical} does not match any built page`);
      else if (normUrl(canonical) !== normUrl(new URL(origin).origin + page.path)) {
        report.warn(
          where,
          `canonical points at another page (${canonical}); right only for a deliberate duplicate`,
        );
      }
    }

    const alternates = doc.links('alternate').filter((l) => l.attrs.hreflang);
    if (alternates.length) {
      const langs = alternates.map((l) => l.attrs.hreflang);
      if (!langs.includes('x-default'))
        report.error(where, 'hreflang alternates have no x-default');
      for (const l of alternates) {
        const { hreflang, href = '' } = l.attrs;
        if (!HREFLANG.test(hreflang))
          report.warn(where, `hreflang="${hreflang}" is not a language(-region) code or x-default`);
        if (!/^https?:\/\//i.test(href))
          report.error(where, `hreflang ${hreflang} href ${href} is not an absolute URL`);
        else if (origin && !onSite(href, origin))
          report.error(where, `hreflang ${hreflang} href ${href} is not on ${origin}`);
        else if (origin) {
          const file = site.resolvePath(urlPath(href));
          if (!file) {
            report.error(where, `hreflang ${hreflang} href ${href} does not match any built page`);
            continue;
          }
          if (hreflang === 'x-default' || !file.endsWith('.html')) continue;
          const back = readDoc(file)
            .links('alternate')
            .filter((a) => a.attrs.hreflang)
            .map((a) => normUrl(a.attrs.href || ''));
          const self = canonical ? normUrl(canonical) : '';
          if (self && !back.includes(self))
            report.error(
              where,
              `hreflang ${hreflang} page ${href} does not link back to ${canonical} (alternates must be reciprocal)`,
            );
        }
      }
      if (
        canonical &&
        !alternates.some((l) => normUrl(l.attrs.href || '') === normUrl(canonical))
      ) {
        report.error(where, 'the hreflang set does not include the page itself');
      }
    }
  }

  for (const [title, paths] of titles) {
    if (paths.length > 1) report.error(paths.join(', '), `share the title "${title}"`);
  }
  for (const [, paths] of descriptions) {
    if (paths.length > 1) report.error(paths.join(', '), 'share one description');
  }

  const home = site.pages.find((p) => p.path === `${site.basePath}/`);
  if (home && !readDoc(home.file).links('icon').length)
    report.warn(home.rel, 'no <link rel="icon"> (add app/icon.* or app/favicon.ico)');

  return report.finish(`${checked} page(s) read from ${site.mode} output`);
});
