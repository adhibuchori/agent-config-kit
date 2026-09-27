#!/usr/bin/env node
// Structured data in the built pages: every <script type="application/ld+json"> parses as JSON,
// names schema.org as its @context, gives every node a @type, carries the minimum properties this
// kit asks of common types, and uses absolute URLs. It proves the markup is well formed; it does
// not promise a rich result. Rule: .claude/rules/web/seo.md. Runs after `next build`.
//
//   node scripts/check/jsonld.mjs [--dir out] [--root .] [--config scripts/check/site.config.json]
import { readFileSync } from 'node:fs';
import { openSite, parseHtml, run } from './lib/site.mjs';

// The kit's minimum per type: what a reader of the data needs to identify the thing. Search
// engines document more for specific features; check those with their own validators.
const REQUIRED = {
  Organization: ['name', 'url'],
  Corporation: ['name', 'url'],
  NGO: ['name', 'url'],
  LocalBusiness: ['name', 'address'],
  WebSite: ['name', 'url'],
  Person: ['name'],
  Service: ['name'],
  Product: ['name'],
  Event: ['name', 'startDate', 'location'],
  Article: ['headline'],
  BlogPosting: ['headline'],
  NewsArticle: ['headline'],
  BreadcrumbList: ['itemListElement'],
  FAQPage: ['mainEntity'],
  JobPosting: ['title', 'description', 'datePosted', 'hiringOrganization'],
};
const URL_KEYS = new Set(['url', 'logo', 'image', 'sameAs', 'item', 'contentUrl', 'thumbnailUrl']);
const LOCAL = /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])(:\d+)?(\/|$)/i;

const types = (node) => [].concat(node['@type'] || []).map(String);

function checkUrls(value, key, where, report) {
  if (typeof value === 'string') {
    if (LOCAL.test(value)) report.error(where, `${key} ${value} points at localhost`);
    else if (!/^https?:\/\//i.test(value))
      report.error(where, `${key} "${value}" is not an absolute http(s) URL`);
  } else if (Array.isArray(value)) value.forEach((v) => checkUrls(v, key, where, report));
  else if (value && typeof value === 'object' && typeof value.url === 'string')
    checkUrls(value.url, `${key}.url`, where, report);
}

function checkNode(node, where, report, path) {
  if (!node || typeof node !== 'object' || Array.isArray(node)) return;
  const t = types(node);
  for (const type of t) {
    for (const prop of REQUIRED[type] || []) {
      const v = node[prop];
      if (v === undefined || v === null || v === '' || (Array.isArray(v) && !v.length)) {
        report.error(where, `${path}${type} has no ${prop}`);
      }
    }
  }
  if (t.includes('BreadcrumbList') && Array.isArray(node.itemListElement)) {
    node.itemListElement.forEach((li, i) => {
      if (!Number.isInteger(li?.position))
        report.error(where, `${path}BreadcrumbList item ${i + 1} has no integer position`);
      if (!li?.name && !li?.item?.name)
        report.error(where, `${path}BreadcrumbList item ${i + 1} has no name`);
      if (!li?.item && i < node.itemListElement.length - 1)
        report.error(where, `${path}BreadcrumbList item ${i + 1} has no item URL`);
    });
  }
  if (t.includes('FAQPage')) {
    for (const q of [].concat(node.mainEntity || [])) {
      if (!types(q || {}).includes('Question') || !q.name || !q.acceptedAnswer?.text) {
        report.error(
          where,
          `${path}FAQPage mainEntity needs Question items with name and acceptedAnswer.text`,
        );
        break;
      }
    }
  }
  for (const [key, value] of Object.entries(node)) {
    if (URL_KEYS.has(key)) checkUrls(value, key, where, report);
    if (key.startsWith('@')) continue;
    for (const child of [].concat(value)) {
      if (child && typeof child === 'object' && (child['@type'] || child['@graph']))
        checkNode(child, where, report, `${path}${key} > `);
    }
  }
}

run('jsonld', ({ args, root, cfg, report }) => {
  const site = openSite(root, cfg, args.dir);
  let blocks = 0;
  for (const page of site.pages) {
    if (page.special) continue;
    const doc = parseHtml(readFileSync(page.file, 'utf8'));
    const scripts = doc
      .all('script')
      .filter((s) => (s.attrs.type || '').toLowerCase() === 'application/ld+json');
    scripts.forEach((s, i) => {
      blocks++;
      const where = `${page.rel} [ld+json ${i + 1}]`;
      const raw = s.text;
      let data;
      try {
        data = JSON.parse(raw);
      } catch (e) {
        const hint = /&(quot|lt|gt|amp);/.test(raw)
          ? " (it was HTML-escaped: render JSON.stringify(data) as the script element's child, with < escaped as \\u003c)"
          : '';
        report.error(where, `not valid JSON: ${e.message}${hint}`);
        return;
      }
      if (raw.includes('<'))
        report.warn(
          where,
          'contains a raw "<": escape it as \\u003c so text can never close the script',
        );
      const roots = Array.isArray(data) ? data : [data];
      for (const node of roots) {
        const ctx = JSON.stringify(node?.['@context'] ?? '');
        if (!/schema\.org/.test(ctx)) report.error(where, 'no @context naming https://schema.org');
        const nodes = Array.isArray(node?.['@graph']) ? node['@graph'] : [node];
        for (const n of nodes) {
          if (!types(n || {}).length) report.error(where, 'a node has no @type');
          checkNode(n, where, report, '');
          if (types(n || {}).includes('FAQPage')) {
            report.info(
              `note ${where}: FAQ rich results are limited to a few authoritative sites; keep the markup only for Q&A the page shows`,
            );
          }
        }
      }
    });
  }
  return report.finish(
    `${blocks} block(s) in ${site.pages.filter((p) => !p.special).length} page(s)`,
  );
});
