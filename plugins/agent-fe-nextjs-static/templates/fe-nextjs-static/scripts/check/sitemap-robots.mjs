#!/usr/bin/env node
// robots.txt and the sitemap of the built site. Production (default): robots does not block the
// site, names the sitemap by absolute URL; the sitemap lists every indexable page exactly once, by
// absolute URL on the production origin, and nothing that is noindex, blocked or missing.
// --env preview: the build must keep search engines out (Disallow: / or noindex on every page).
// Rule: .claude/rules/web/seo.md. Runs after `next build`.
//
//   node scripts/check/sitemap-robots.mjs [--env production|preview] [--dir out] [--root .]
import { readFileSync } from 'node:fs';
import {
  UsageError,
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

const MAX_URLS = 50000;

/** robots.txt as { groups: [{ agents, rules: [{ allow, path }] }], sitemaps }. */
function parseRobots(text) {
  const groups = [];
  const sitemaps = [];
  let current = null;
  let lastWasAgent = false;
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.replace(/#.*/, '').trim();
    const m = line.match(/^([A-Za-z-]+)\s*:\s*(.*)$/);
    if (!m) continue;
    const key = m[1].toLowerCase();
    const value = m[2].trim();
    if (key === 'sitemap') {
      sitemaps.push(value);
      continue;
    }
    if (key === 'user-agent') {
      if (!lastWasAgent || !current) {
        current = { agents: [], rules: [] };
        groups.push(current);
      }
      current.agents.push(value.toLowerCase());
      lastWasAgent = true;
      continue;
    }
    lastWasAgent = false;
    if (current && (key === 'allow' || key === 'disallow'))
      current.rules.push({ allow: key === 'allow', path: value });
  }
  return { groups, sitemaps };
}

function ruleRe(path) {
  const anchored = path.endsWith('$');
  const body = (anchored ? path.slice(0, -1) : path)
    .replace(/[.+?^{}()|[\]\\]/g, '\\$&')
    .replace(/\*/g, '.*');
  return new RegExp(`^${body}${anchored ? '$' : ''}`);
}

/** Google's reading: the longest matching rule wins, Allow on a tie; an empty Disallow allows. */
function allowed(groups, path) {
  const group = groups.find((g) => g.agents.includes('*'));
  if (!group) return true;
  let best = null;
  for (const r of group.rules) {
    if (!r.path) continue;
    if (!ruleRe(r.path).test(path)) continue;
    if (
      !best ||
      r.path.length > best.path.length ||
      (r.path.length === best.path.length && r.allow)
    )
      best = r;
  }
  return !best || best.allow;
}

const locs = (xml, tag) =>
  [...xml.matchAll(new RegExp(`<${tag}>\\s*<loc>([^<]+)</loc>`, 'g'))].map((m) => m[1].trim());

run('sitemap-robots', ({ args, root, cfg, report }) => {
  const env = args.env || 'production';
  if (!['production', 'preview'].includes(env))
    throw new UsageError('--env must be production or preview');
  const site = openSite(root, cfg, args.dir);
  const origin = siteUrl(cfg);

  const docs = new Map();
  const readDoc = (file) => {
    if (!docs.has(file)) docs.set(file, parseHtml(readFileSync(file, 'utf8')));
    return docs.get(file);
  };
  const pages = site.pages.filter((p) => !p.special);

  const robotsFile = site.resolvePath(`${site.basePath}/robots.txt`);
  const robots = robotsFile ? parseRobots(readFileSync(robotsFile, 'utf8')) : null;
  if (!robots)
    report.error(
      'robots.txt',
      'missing: add app/robots.ts (with export const dynamic = "force-static" under output: export)',
    );

  if (env === 'preview') {
    const blocked = robots && !allowed(robots.groups, `${site.basePath}/`);
    const allNoindex = pages.length > 0 && pages.every((p) => isNoindex(readDoc(p.file)));
    if (!blocked && !allNoindex) {
      report.error(
        'preview',
        'this build can be indexed: a preview must send Disallow: / in robots.txt or noindex on every page, chosen from the deploy environment (a host-set X-Robots-Tag header cannot be seen here: check it on the preview URL)',
      );
    }
    return report.finish(`preview build, ${pages.length} page(s)`);
  }

  if (!origin)
    report.error(
      'config',
      'siteUrl is not set: put the production origin in scripts/check/site.config.json or NEXT_PUBLIC_SITE_URL',
    );
  if (robots) {
    if (!allowed(robots.groups, `${site.basePath}/`))
      report.error(
        'robots.txt',
        'blocks the home page for every crawler (Disallow: /): a production build must be crawlable',
      );
    if (!robots.sitemaps.length) report.error('robots.txt', 'no Sitemap: line');
    for (const s of robots.sitemaps) {
      if (!/^https?:\/\//i.test(s))
        report.error('robots.txt', `Sitemap ${s} is not an absolute URL`);
      else if (origin && !onSite(s, origin))
        report.error('robots.txt', `Sitemap ${s} is not on ${origin}`);
    }
  }

  // The sitemap files: those robots names on this site, else /sitemap.xml; an index is followed.
  const queue = (robots?.sitemaps || []).filter((s) => origin && onSite(s, origin)).map(urlPath);
  if (!queue.length) queue.push(`${site.basePath}/sitemap.xml`);
  const listed = new Map();
  const alternates = [];
  const done = new Set();
  while (queue.length) {
    const p = queue.shift();
    if (done.has(p)) continue;
    done.add(p);
    const file = site.resolvePath(p);
    if (!file) {
      report.error(
        p,
        'sitemap missing: add app/sitemap.ts (with export const dynamic = "force-static" under output: export)',
      );
      continue;
    }
    const xml = readFileSync(file, 'utf8');
    if (/<sitemapindex[\s>]/.test(xml)) {
      for (const child of locs(xml, 'sitemap')) {
        if (origin && onSite(child, origin)) queue.push(urlPath(child));
        else report.error(p, `child sitemap ${child} is not on ${origin || 'the site'}`);
      }
      continue;
    }
    if (!/<urlset[\s>]/.test(xml)) {
      report.error(p, 'is not a <urlset> or <sitemapindex> document');
      continue;
    }
    for (const block of xml.match(/<url>[\s\S]*?<\/url>/g) || []) {
      const loc = (block.match(/<loc>([^<]+)<\/loc>/) || [])[1]?.trim();
      if (!loc) {
        report.error(p, 'a <url> without <loc>');
        continue;
      }
      const lastmod = (block.match(/<lastmod>([^<]+)<\/lastmod>/) || [])[1];
      if (
        lastmod &&
        !/^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:\d{2}))?$/.test(
          lastmod.trim(),
        )
      ) {
        report.warn(p, `${loc}: lastmod "${lastmod}" is not a W3C date`);
      }
      const key = normUrl(loc);
      if (listed.has(key)) report.error(p, `${loc} is listed twice`);
      listed.set(key, { loc, sitemap: p });
      for (const m of block.matchAll(/<xhtml:link\b([^>]*)\/?>/g)) {
        const href = (m[1].match(/href="([^"]*)"/) || [])[1] || '';
        const lang = (m[1].match(/hreflang="([^"]*)"/) || [])[1] || '';
        alternates.push({ loc, href, lang, sitemap: p });
      }
    }
  }
  if (listed.size > MAX_URLS)
    report.error(
      'sitemap',
      `${listed.size} URLs; one sitemap holds at most ${MAX_URLS} (split it with an index)`,
    );

  for (const { loc, sitemap } of listed.values()) {
    if (!/^https?:\/\//i.test(loc)) {
      report.error(sitemap, `${loc} is not an absolute URL`);
      continue;
    }
    if (origin && !onSite(loc, origin)) {
      report.error(sitemap, `${loc} is not on ${origin}`);
      continue;
    }
    const path = urlPath(loc);
    const file = site.resolvePath(path);
    if (!file) {
      report.error(sitemap, `${loc} does not match any built page`);
      continue;
    }
    if (robots && !allowed(robots.groups, path))
      report.error(sitemap, `${loc} is blocked by robots.txt`);
    if (file.endsWith('.html')) {
      const doc = readDoc(file);
      if (isNoindex(doc))
        report.error(sitemap, `${loc} is noindex; a sitemap lists only pages you want indexed`);
      const canonical = doc.links('canonical')[0]?.attrs.href;
      if (canonical && normUrl(canonical) !== normUrl(loc))
        report.error(
          sitemap,
          `${loc} declares another canonical (${canonical}); list the canonical URL`,
        );
    }
  }

  const byLoc = new Map();
  for (const a of alternates) byLoc.set(a.loc, [...(byLoc.get(a.loc) || []), a]);
  for (const [loc, list] of byLoc) {
    if (!list.some((a) => a.lang === 'x-default'))
      report.warn(list[0].sitemap, `${loc}: hreflang alternates without x-default`);
    for (const a of list) {
      if (!/^https?:\/\//i.test(a.href) || (origin && !onSite(a.href, origin)))
        report.error(
          a.sitemap,
          `${loc}: alternate ${a.lang} ${a.href} is not an absolute URL on the site`,
        );
      else if (!site.resolvePath(urlPath(a.href)))
        report.error(
          a.sitemap,
          `${loc}: alternate ${a.lang} ${a.href} does not match any built page`,
        );
    }
  }

  if (origin) {
    const host = new URL(origin).origin;
    for (const page of pages) {
      if (matchesAny(page.path, cfg.sitemapExclude)) continue;
      const doc = readDoc(page.file);
      if (isNoindex(doc)) {
        report.warn(
          page.rel,
          'is noindex in a production build: add its path to sitemapExclude if that is deliberate',
        );
        continue;
      }
      if (robots && !allowed(robots.groups, page.path)) continue;
      if (!listed.has(normUrl(host + page.path)))
        report.error(
          page.rel,
          `indexable page ${page.path} is missing from the sitemap (or add it to sitemapExclude)`,
        );
    }
  }
  return report.finish(`${listed.size} sitemap URL(s), ${pages.length} page(s)`);
});
