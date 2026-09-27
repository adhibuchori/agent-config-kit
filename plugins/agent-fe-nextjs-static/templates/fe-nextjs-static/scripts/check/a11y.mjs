#!/usr/bin/env node
// Accessibility of the built pages in a real browser. It serves the build on 127.0.0.1 (serve.mjs)
// and runs the project's own checker over every page that is not an error page:
//   pa11y-ci   with the axe runner and the standard in a11y.standard (WCAG2AA by default); the
//              `defaults` of a .pa11yci.json in the project are kept, its `urls` are not used
//   axe        @axe-core/cli with the WCAG A and AA tags; it needs a ChromeDriver that matches Chrome
// Nothing is downloaded: the checker must be a dev dependency (node_modules/.bin). An automated
// checker finds a part of the problems only; /agent-fe-nextjs-static:a11y-audit covers the rest.
// Rule: AGENTS.md § E (accessibility). Runs after `next build`.
//
//   node scripts/check/a11y.mjs [--tool pa11y-ci|axe] [--only /,/about] [--dir out] [--root .] [--config FILE]
//
// Exit: 0 no violations, 1 violations, 2 the check could not run (no build, no checker, a crash).
import { spawn } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { UsageError, matchesAny, openSite, run } from './lib/site.mjs';
import { startServer } from './serve.mjs';

const TOOLS = ['pa11y-ci', 'axe'];
const AXE_TAGS = {
  WCAG2A: 'wcag2a,wcag21a',
  WCAG2AA: 'wcag2a,wcag2aa,wcag21a,wcag21aa',
  WCAG2AAA: 'wcag2a,wcag2aa,wcag2aaa,wcag21a,wcag21aa',
};

/** Runs a tool without blocking the server in this process; resolves to { status, stdout }. */
function spawnTool(cmd, argv, cwd, capture) {
  return new Promise((resolve) => {
    const child = spawn(cmd, argv, {
      cwd,
      stdio: ['ignore', capture ? 'pipe' : 'inherit', 'inherit'],
    });
    let stdout = '';
    if (capture) child.stdout.on('data', (d) => (stdout += d));
    child.on('error', (e) => resolve({ status: 127, stdout: '', error: e.message }));
    child.on('close', (status, signal) =>
      resolve({ status: status ?? (signal ? 128 : 1), stdout }),
    );
  });
}

/** The `defaults` of the project's own pa11y-ci config (JSON only), or {}. */
function userPa11yDefaults(root) {
  for (const name of ['.pa11yci.json', '.pa11yci']) {
    const p = join(root, name);
    if (!existsSync(p)) continue;
    try {
      const data = JSON.parse(readFileSync(p, 'utf8'));
      return data && typeof data.defaults === 'object' && data.defaults ? data.defaults : {};
    } catch (e) {
      throw new UsageError(`${name} is not JSON: ${e.message}`);
    }
  }
  return {};
}

async function viaPa11y(bin, urls, root, cfg, report) {
  const defaults = { standard: cfg.a11y.standard, runners: ['axe'], ...userPa11yDefaults(root) };
  const dir = mkdtempSync(join(tmpdir(), 'a11y-'));
  const file = join(dir, 'pa11yci.json');
  writeFileSync(file, `${JSON.stringify({ defaults, urls }, null, 2)}\n`);
  try {
    const { status, error } = await spawnTool(bin, ['--config', file], root, false);
    // pa11y-ci exits 2 when a page has errors and 1 when it could not run at all.
    if (status === 2)
      report.error('pa11y-ci', 'reported accessibility errors; its own output lists each one');
    else if (status !== 0)
      throw new UsageError(
        `pa11y-ci could not run (exit ${status}${error ? `: ${error}` : ''}); its own output above says why`,
      );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

async function viaAxe(bin, urls, root, cfg, report, base) {
  const tags = AXE_TAGS[cfg.a11y.standard] || AXE_TAGS.WCAG2AA;
  // --stdout prints the results as JSON and exits 0 whatever they hold, so a crash (non-zero) and
  // a violation (in the JSON) can be told apart; axe's own --exit gives both the same code.
  const { status, stdout, error } = await spawnTool(
    bin,
    [...urls, '--tags', tags, '--stdout'],
    root,
    true,
  );
  if (status !== 0)
    throw new UsageError(`axe could not run (exit ${status}${error ? `: ${error}` : ''})`);
  let results;
  try {
    results = JSON.parse(stdout);
  } catch {
    throw new UsageError('axe printed no JSON results');
  }
  for (const r of [].concat(results)) {
    const where = (r.url || '').startsWith(base) ? r.url.slice(base.length) || '/' : r.url || '?';
    for (const v of r.violations || []) {
      report.error(
        where,
        `${v.id} (${v.impact || 'unknown impact'}): ${v.help}; ${(v.nodes || []).length} element(s)`,
      );
    }
  }
}

run('a11y', async ({ args, root, cfg, report }) => {
  if (args.tool && !TOOLS.includes(args.tool))
    throw new UsageError('--tool must be pa11y-ci or axe');
  const site = openSite(root, cfg, args.dir);
  const binOf = (name) => join(root, 'node_modules', '.bin', name);
  const tool = args.tool || TOOLS.find((t) => existsSync(binOf(t)));
  if (!tool || !existsSync(binOf(tool))) {
    throw new UsageError(
      `${tool ? `node_modules/.bin/${tool} not found` : 'no accessibility checker in node_modules/.bin'}: add pa11y-ci (it brings its own browser) or @axe-core/cli (it needs a ChromeDriver that matches Chrome) as a dev dependency`,
    );
  }

  const pages = site.pages
    .filter((p) => !p.special && !matchesAny(p.path, cfg.a11y.exclude))
    .map((p) => p.path);
  const only = args.only
    ? args.only
        .split(',')
        .map((s) => s.trim())
        .filter(Boolean)
    : null;
  const unknown = (only || []).filter((p) => !pages.includes(p));
  if (unknown.length) throw new UsageError(`not a built page (or excluded): ${unknown.join(', ')}`);
  const paths = only || pages;
  if (!paths.length) throw new UsageError('no pages to check');

  const server = await startServer(site, 0);
  try {
    const urls = paths.map((p) => server.url + p);
    report.info(
      `${tool} on ${urls.length} page(s) of the ${site.mode} build, served at ${server.url}`,
    );
    if (tool === 'pa11y-ci') await viaPa11y(binOf(tool), urls, root, cfg, report);
    else await viaAxe(binOf(tool), urls, root, cfg, report, server.url);
  } finally {
    await server.close();
  }
  return report.finish(
    `${paths.length} page(s); an automated checker finds only part of the problems`,
  );
});
