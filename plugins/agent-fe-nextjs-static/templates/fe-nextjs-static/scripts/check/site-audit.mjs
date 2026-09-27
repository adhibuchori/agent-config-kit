#!/usr/bin/env node
// Runs every static-site check against the built site and prints one table: the post-build gate
// (CI after `next build`, /agent-fe-nextjs-static:seo-audit and :launch-checklist). Each check can
// also run alone; see its header. The browser checks (a11y.mjs, Lighthouse CI) are not in this
// list: they need a checker installed and a browser, so they run on their own.
//
//   node scripts/check/site-audit.mjs [--only a,b] [--env production|preview] [--dir out] [--root .] [--config FILE]
//
// Exit: 0 every check passed (warnings allowed), 1 a check failed, 2 a check could not run.
import { spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const CHECKS = [
  ['static-export', []],
  ['sitemap-robots', []],
  ['metadata', []],
  ['og-image', []],
  ['jsonld', []],
  ['broken-links', []],
  ['image-budget', []],
  ['font-budget', []],
  ['bundle-budget', []],
  ['security-headers', ['--verify-hashes']],
];
const FORWARD = ['dir', 'root', 'config', 'env'];

const here = dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
const opts = {};
for (let i = 0; i < argv.length; i++) {
  const m = argv[i].match(/^--([a-z-]+)(?:=(.*))?$/);
  if (!m) {
    console.error(`site-audit: unexpected argument ${argv[i]}`);
    process.exit(2);
  }
  opts[m[1]] = m[2] ?? argv[++i];
  if (opts[m[1]] === undefined) {
    console.error(`site-audit: --${m[1]} needs a value`);
    process.exit(2);
  }
}
for (const k of Object.keys(opts)) {
  if (![...FORWARD, 'only'].includes(k)) {
    console.error(`site-audit: unknown option --${k}`);
    process.exit(2);
  }
}
const only = opts.only ? opts.only.split(',').map((s) => s.trim()) : null;
const unknown = (only || []).filter((n) => !CHECKS.some(([c]) => c === n));
if (unknown.length) {
  console.error(`site-audit: no check named ${unknown.join(', ')}`);
  process.exit(2);
}

const rows = [];
for (const [name, extra] of CHECKS) {
  if (only && !only.includes(name)) continue;
  const args = [join(here, `${name}.mjs`), ...extra];
  for (const k of FORWARD) {
    if (opts[k] === undefined) continue;
    if (k === 'env' && name !== 'sitemap-robots') continue;
    args.push(`--${k}`, opts[k]);
  }
  const start = Date.now();
  const r = spawnSync(process.execPath, args, { stdio: 'inherit' });
  rows.push([name, r.status ?? 2, ((Date.now() - start) / 1000).toFixed(1)]);
}

console.log('\ncheck              exit   secs');
for (const [name, code, secs] of rows)
  console.log(`${name.padEnd(18)} ${String(code).padStart(4)} ${secs.padStart(6)}`);
const worst = rows.some(([, c]) => c === 2) ? 2 : rows.some(([, c]) => c !== 0) ? 1 : 0;
console.log(`\n${rows.length} check(s), ${rows.filter(([, c]) => c !== 0).length} failed`);
process.exit(worst);
