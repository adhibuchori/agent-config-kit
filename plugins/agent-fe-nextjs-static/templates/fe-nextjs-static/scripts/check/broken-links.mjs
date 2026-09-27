#!/usr/bin/env node
// Internal links and assets of the built pages resolve: every same-site href/src/srcset (links,
// images, scripts, stylesheets, icons, media) names a file in the build, and every #fragment names
// an id on its target page. External links are counted, never fetched (no network); http:
// subresources are errors (mixed content) and javascript: URLs are refused. Runs after `next build`.
//
//   node scripts/check/broken-links.mjs [--dir out] [--root .] [--config scripts/check/site.config.json]
import { readFileSync } from 'node:fs';
import { onSite, openSite, parseHtml, run, siteUrl, urlPath } from './lib/site.mjs';

const SKIP_SCHEMES = /^(mailto|tel|sms|data|blob|about):/i;
const ATTRS = {
  a: ['href'],
  area: ['href'],
  link: ['href'],
  img: ['src', 'srcset'],
  source: ['src', 'srcset'],
  script: ['src'],
  video: ['src', 'poster'],
  audio: ['src'],
  track: ['src'],
  iframe: ['src'],
  embed: ['src'],
};
const NOT_FETCHED_RELS = ['preconnect', 'dns-prefetch', 'alternate', 'canonical'];

const srcsetUrls = (v) =>
  v
    .split(',')
    .map((part) => part.trim().split(/\s+/)[0])
    .filter(Boolean);

run('broken-links', ({ args, root, cfg, report }) => {
  const site = openSite(root, cfg, args.dir);
  const origin = siteUrl(cfg);
  const idCache = new Map();
  const idsOf = (file) => {
    if (!idCache.has(file)) {
      const doc = parseHtml(readFileSync(file, 'utf8'));
      const ids = new Set();
      for (const t of doc.tags) {
        if (t.attrs.id) ids.add(t.attrs.id);
        if (t.name === 'a' && t.attrs.name) ids.add(t.attrs.name);
      }
      idCache.set(file, ids);
    }
    return idCache.get(file);
  };

  let internal = 0;
  let external = 0;
  for (const page of site.pages) {
    const doc = parseHtml(readFileSync(page.file, 'utf8'));
    const base = new URL(page.path, 'http://site.invalid');
    for (const tag of doc.tags) {
      const names = ATTRS[tag.name];
      if (!names) continue;
      const rels = (tag.attrs.rel || '').toLowerCase().split(/\s+/);
      if (tag.name === 'link' && rels.some((r) => NOT_FETCHED_RELS.includes(r))) continue;
      for (const attr of names) {
        const value = tag.attrs[attr];
        if (value === undefined) continue;
        const urls = attr === 'srcset' ? srcsetUrls(value) : [value.trim()];
        for (const u of urls) {
          const where = `${page.rel} <${tag.name} ${attr}="${u}">`;
          if (!u) {
            if (tag.name === 'a' || tag.name === 'img') report.error(where, 'empty URL');
            continue;
          }
          if (/^javascript:/i.test(u)) {
            report.error(where, 'javascript: URL; use a <button> for actions');
            continue;
          }
          if (SKIP_SCHEMES.test(u)) continue;
          const absolute = /^[a-z][a-z0-9+.-]*:/i.test(u) || u.startsWith('//');
          if (absolute && !(origin && onSite(u.startsWith('//') ? `https:${u}` : u, origin))) {
            external++;
            if (/^http:/i.test(u) && tag.name !== 'a')
              report.error(where, 'loads over http: from an https page (mixed content is blocked)');
            else if (/^http:/i.test(u)) report.warn(where, 'links over http:');
            if (
              tag.name === 'a' &&
              tag.attrs.target === '_blank' &&
              !/\bnoopener\b/.test(rels.join(' '))
            ) {
              report.warn(where, 'target="_blank" without rel="noopener noreferrer"');
            }
            continue;
          }
          internal++;
          if (u.startsWith('#')) {
            const frag = decodeURIComponent(u.slice(1));
            if (frag && frag !== 'top' && !idsOf(page.file).has(frag))
              report.error(where, `no element with id "${frag}" on this page`);
            continue;
          }
          const resolved = absolute
            ? new URL(u.startsWith('//') ? `https:${u}` : u)
            : new URL(u, base);
          const path = urlPath(resolved.href) ?? resolved.pathname;
          const file = site.resolvePath(path);
          if (!file) {
            report.error(where, `nothing in the build serves ${path}`);
            continue;
          }
          const frag = resolved.hash ? decodeURIComponent(resolved.hash.slice(1)) : '';
          if (frag && frag !== 'top' && file.endsWith('.html') && !idsOf(file).has(frag)) {
            report.error(where, `${path} has no element with id "${frag}"`);
          }
        }
      }
    }
  }
  return report.finish(
    `${internal} internal and ${external} external reference(s) in ${site.pages.length} page(s); external links are not fetched`,
  );
});
