#!/usr/bin/env node
// First-load weight of every built page: the JavaScript it runs (same-site <script src> files plus
// inline scripts) and the CSS it loads (stylesheets plus inline <style>), gzipped at level 6 the way
// most hosts send them. Each page must stay under bundle.maxJsKB and bundle.maxCssKB from
// scripts/check/site.config.json. Scripts from other hosts are listed, not measured (no network).
// --report prints every page's numbers, heaviest first: run it on the first build to see what the
// framework itself costs, then set the budget to what you ship plus some headroom.
// Rule: .claude/rules/web/performance.md. Runs after `next build`.
//
//   node scripts/check/bundle-budget.mjs [--report] [--dir out] [--root .] [--config FILE]
import { readFileSync } from 'node:fs';
import { gzipSync } from 'node:zlib';
import { onSite, openSite, parseHtml, run, siteUrl, urlPath } from './lib/site.mjs';

const EXECUTABLE = new Set(['', 'text/javascript', 'application/javascript', 'module']);
const kb = (bytes) => Math.round((bytes / 1024) * 10) / 10;

run(
  'bundle-budget',
  ({ args, root, cfg, report }) => {
    const site = openSite(root, cfg, args.dir);
    const origin = siteUrl(cfg);
    const { maxJsKB, maxCssKB } = cfg.bundle;
    const gz = new Map();
    const sizeOf = (file) => {
      if (!gz.has(file)) gz.set(file, gzipSync(readFileSync(file), { level: 6 }).length);
      return gz.get(file);
    };
    const local = (u) =>
      !/^[a-z][a-z0-9+.-]*:|^\/\//i.test(u) ||
      (origin && onSite(u.startsWith('//') ? `https:${u}` : u, origin));

    const rows = [];
    const external = new Set();
    for (const page of site.pages) {
      const doc = parseHtml(readFileSync(page.file, 'utf8'));
      const base = new URL(page.path, 'http://site.invalid');
      const resolve = (u) => {
        const p = urlPath(new URL(u.startsWith('//') ? `https:${u}` : u, base).href);
        return p ? site.resolvePath(p) : null;
      };
      let js = 0;
      let css = 0;
      const seen = new Set();
      for (const s of doc.all('script')) {
        if (!EXECUTABLE.has((s.attrs.type || '').toLowerCase())) continue;
        if (s.attrs.src === undefined) {
          js += gzipSync(s.text || '', { level: 6 }).length;
          continue;
        }
        if (!local(s.attrs.src)) {
          external.add(s.attrs.src);
          continue;
        }
        const file = resolve(s.attrs.src);
        if (!file)
          report.warn(
            page.rel,
            `<script src="${s.attrs.src}"> is not in the build (broken-links.mjs names it)`,
          );
        else if (!seen.has(file)) {
          seen.add(file);
          js += sizeOf(file);
        }
      }
      for (const l of doc.links('stylesheet')) {
        const href = l.attrs.href || '';
        if (!href || !local(href)) {
          if (href) external.add(href);
          continue;
        }
        const file = resolve(href);
        if (file && !seen.has(file)) {
          seen.add(file);
          css += sizeOf(file);
        }
      }
      for (const s of doc.all('style')) css += gzipSync(s.text || '', { level: 6 }).length;
      rows.push({ page, js, css });
      if (kb(js) > maxJsKB)
        report.error(
          page.rel,
          `${kb(js)} KB of JavaScript (gzipped) on first load; budget ${maxJsKB} KB`,
        );
      if (kb(css) > maxCssKB)
        report.error(
          page.rel,
          `${kb(css)} KB of CSS (gzipped) on first load; budget ${maxCssKB} KB`,
        );
    }
    for (const u of [...external].toSorted())
      report.warn(
        'build',
        `loads ${u} from another host: not measured here, and it costs a connection`,
      );

    if (args.report) {
      console.log(`\npage${' '.repeat(36)}   js KB  css KB`);
      for (const r of rows.toSorted((a, b) => b.js - a.js)) {
        console.log(
          `${r.page.path.padEnd(40)} ${String(kb(r.js)).padStart(7)} ${String(kb(r.css)).padStart(7)}`,
        );
      }
      console.log('');
    }
    const heaviest = rows.reduce((m, r) => (r.js > m ? r.js : m), 0);
    return report.finish(
      `${rows.length} page(s), heaviest ${kb(heaviest)} KB of JavaScript (budget ${maxJsKB} KB)`,
    );
  },
  { switches: ['report'] },
);
