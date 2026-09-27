#!/usr/bin/env node
// Keeps a static site static, from the source (no build needed; fast enough for pre-commit).
//
// export mode (next.config sets output: 'export'): refuses what `next build` either rejects late
// or drops without failing: a proxy/middleware file, headers()/redirects()/rewrites() in
// next.config, route handlers other than a force-static GET, server actions, request-time APIs
// (cookies(), headers(), draftMode(), searchParams in a server page), force-dynamic, ISR
// revalidate, dynamicParams = true, a dynamic segment without generateStaticParams, next/image
// without an export-safe loader, and a missing not-found page.
// ssg-with-endpoints mode: pages stay prerendered (no force-dynamic, request-time APIs or
// dynamic segments without generateStaticParams); route handlers, server actions and request-time
// APIs live only under the `endpoints` globs of scripts/check/site.config.json.
// Also warns about app machinery a brochure site does not need. Rule: .claude/rules/web/static-export.md.
//
//   node scripts/check/static-export.mjs [--mode export|ssg-with-endpoints] [--root .] [--config FILE]
import { existsSync, readFileSync } from 'node:fs';
import { basename, dirname, join, relative } from 'node:path';
import {
  UsageError,
  detectMode,
  filesUnder,
  matchesAny,
  readNextConfig,
  run,
  sourceFiles,
  stripComments,
  toPosix,
} from './lib/site.mjs';

const CODE = /\.(tsx?|jsx?|mjs|cjs|mts|cts)$/;
const METHODS = ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'];
const MACHINERY = [
  ['@tanstack/react-query', 'a client data cache'],
  ['swr', 'a client data cache'],
  ['@apollo/client', 'a GraphQL client'],
  ['urql', 'a GraphQL client'],
  ['next-auth', 'an auth library'],
  ['@auth/', 'an auth library'],
  ['@clerk/', 'an auth library'],
  ['better-auth', 'an auth library'],
  ['zustand', 'a global store'],
  ['@reduxjs/toolkit', 'a global store'],
];
const SPECIAL =
  /^(page|layout|route|template|default|loading|error|not-found|global-error)\.(tsx?|jsx?|mdx)$/;
const METADATA_ROUTE =
  /^(robots|sitemap|manifest|opengraph-image|twitter-image|icon|apple-icon)\.(tsx?|jsx?)$/;

const exported = (src, name) =>
  new RegExp(
    `export\\s+(async\\s+)?function\\s+${name}\\b|export\\s+(const|let|var)\\s+${name}\\b|export\\s*{[^}]*\\b${name}\\b[^}]*}`,
  ).test(src);

run('static-export', ({ args, root, cfg, report }) => {
  if (args.mode && !['export', 'ssg-with-endpoints'].includes(args.mode))
    throw new UsageError('--mode must be export or ssg-with-endpoints');
  const mode = args.mode || detectMode(root, cfg);
  const exportMode = mode === 'export';
  const nc = readNextConfig(root);
  const appDirs = ['app', 'src/app'].map((d) => join(root, d)).filter((d) => existsSync(d));
  if (!appDirs.length)
    throw new UsageError('no app/ or src/app/ folder: this check reads an App Router project');
  const rel = (f) => toPosix(relative(root, f));
  const isEndpoint = (f) => !exportMode && matchesAny(rel(f), cfg.endpoints);
  const sources = new Map();
  const read = (f) => {
    if (!sources.has(f)) sources.set(f, stripComments(readFileSync(f, 'utf8')));
    return sources.get(f);
  };

  // next.config
  if (exportMode && nc) {
    for (const key of ['headers', 'redirects', 'rewrites']) {
      if (new RegExp(`\\b(async\\s+)?${key}\\s*(\\(|:)`).test(nc.text)) {
        report.error(
          nc.file,
          `${key}() is ignored under output: 'export' (the build only warns): move it to the host's config`,
        );
      }
    }
  }
  const usesNextImage = sourceFiles(root).some(
    (f) => CODE.test(f) && /from\s+['"]next\/image['"]/.test(read(f)),
  );
  if (
    exportMode &&
    usesNextImage &&
    !(nc && /\bunoptimized\s*:\s*true\b|\bloader(File)?\s*:/.test(nc.text))
  ) {
    report.error(
      nc ? nc.file : 'next.config',
      'next/image with the default loader cannot be exported: set images: { unoptimized: true } or a custom loader',
    );
  }

  // proxy / middleware
  for (const base of ['', 'src/']) {
    for (const name of ['middleware', 'proxy']) {
      for (const ext of ['ts', 'js', 'mjs', 'tsx']) {
        const f = join(root, `${base}${name}.${ext}`);
        if (!existsSync(f)) continue;
        if (exportMode)
          report.error(
            rel(f),
            `a ${name} file does not run in a static export (the build only warns): do its work at build time or in the host's config`,
          );
        else
          report.warn(
            rel(f),
            `runs on every request: keep it to locale routing or headers, never page data`,
          );
      }
    }
  }

  // The app tree: special files, dynamic segments, not-found.
  const appFiles = appDirs.flatMap((d) =>
    filesUnder(d, ['node_modules'])
      .filter((f) => CODE.test(f) || f.endsWith('.mdx'))
      .map((f) => ({ f, appDir: d })),
  );
  if (!appFiles.some(({ f }) => /^not-found\.(tsx?|jsx?|mdx)$/.test(basename(f)))) {
    report.error(
      rel(appDirs[0]),
      "no not-found page: add not-found.tsx so a wrong URL gets the site's own 404 (it becomes 404.html)",
    );
  }

  for (const { f, appDir } of appFiles) {
    const name = basename(f);
    const src = read(f);
    const where = rel(f);
    const endpoint = isEndpoint(f);

    if (/^route\.(tsx?|jsx?)$/.test(name) || METADATA_ROUTE.test(name)) {
      const methods = METHODS.filter((m) => exported(src, m));
      if (exportMode) {
        const writes = methods.filter((m) => m !== 'GET' && m !== 'HEAD');
        if (writes.length)
          report.error(
            where,
            `exports ${writes.join(', ')}: a static export has no server, so this endpoint will not exist (the build passes and the file is missing); post the form to a separate endpoint`,
          );
        if (
          !/export\s+const\s+dynamic\s*=\s*['"]force-static['"]/.test(src) &&
          !/export\s+const\s+revalidate\s*=\s*false\b/.test(src)
        ) {
          report.error(
            where,
            "needs export const dynamic = 'force-static' under output: export (next build fails without it)",
          );
        }
      } else if (name.startsWith('route.') && !endpoint) {
        report.error(
          where,
          'a route handler outside the endpoints globs in scripts/check/site.config.json: move it, or add its folder to endpoints',
        );
      }
    }

    if (!SPECIAL.test(name) && !METADATA_ROUTE.test(name)) continue;
    const isPageLike = /^(page|layout|template|default)\./.test(name);
    if (/export\s+const\s+dynamic\s*=\s*['"]force-dynamic['"]/.test(src) && !endpoint) {
      report.error(
        where,
        "force-dynamic renders on every request: a static site prerenders ('force-static' or nothing)",
      );
    }
    const revalidate = src.match(/export\s+const\s+revalidate\s*=\s*(\d+)/);
    if (exportMode && revalidate && Number(revalidate[1]) > 0)
      report.error(
        where,
        `revalidate = ${revalidate[1]} (ISR) needs a server: remove it, rebuild to update`,
      );
    if (exportMode && /export\s+const\s+dynamicParams\s*=\s*true\b/.test(src))
      report.error(
        where,
        'dynamicParams = true renders unknown params on demand: not possible in a static export',
      );
    if (
      isPageLike &&
      name.startsWith('page.') &&
      !/^\s*['"]use client['"]/.test(src) &&
      /\bsearchParams\b/.test(src)
    ) {
      report.error(
        where,
        'reads searchParams in a server page, which makes it request-time: read them in a client component inside <Suspense>',
      );
    }

    // Dynamic segments between the app root and this page need generateStaticParams in the page
    // or in a layout at or below the segment.
    if (
      !endpoint &&
      (/^(page|route)\./.test(name) ||
        (METADATA_ROUTE.test(name) && !/^(robots|sitemap|manifest)\./.test(name)))
    ) {
      const segs = toPosix(relative(appDir, dirname(f)))
        .split('/')
        .filter(Boolean);
      segs.forEach((seg, i) => {
        if (!/^\[.+\]$/.test(seg)) return;
        const dirs = segs.slice(0, i + 1);
        const candidates = [f];
        for (let j = i + 1; j <= segs.length; j++) {
          const d = join(appDir, ...segs.slice(0, j));
          for (const ext of ['tsx', 'ts', 'jsx', 'js']) candidates.push(join(d, `layout.${ext}`));
        }
        const has = candidates.some(
          (c) => existsSync(c) && exported(read(c), 'generateStaticParams'),
        );
        if (!has) {
          report.error(
            where,
            `dynamic segment ${dirs.join('/')} has no generateStaticParams in this ${name.split('.')[0]} or a layout at or below the segment: ${exportMode ? 'next build fails' : 'the page renders on demand instead of at build'}`,
          );
        }
      });
    }
  }

  // Server actions and request-time APIs anywhere in the source.
  for (const f of sourceFiles(root)) {
    if (!CODE.test(f) || basename(f).startsWith('next.config')) continue;
    const src = read(f);
    const where = rel(f);
    const endpoint = isEndpoint(f);
    if (/['"]use server['"]/.test(src) && !endpoint) {
      report.error(
        where,
        exportMode
          ? "a server action ('use server') cannot run in a static export: post to an endpoint instead"
          : "a server action ('use server') outside the endpoints globs",
      );
    }
    if (
      /from\s+['"]next\/headers['"]/.test(src) &&
      /\b(cookies|headers|draftMode)\s*\(/.test(src) &&
      !endpoint
    ) {
      report.error(
        where,
        'cookies()/headers()/draftMode() make every page that uses this request-time: keep request data in an endpoint',
      );
    }
    for (const [pkg, what] of MACHINERY) {
      const re = new RegExp(
        `from\\s+['"]${pkg.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&')}${pkg.endsWith('/') ? '' : '(/[^\'"]*)?[\'"]'}`,
      );
      if (re.test(src))
        report.warn(
          where,
          `imports ${pkg} (${what}): a static page rarely needs it; see .claude/rules/web/no-app-machinery.md`,
        );
    }
  }

  return report.finish(`${mode} mode, ${appFiles.length} app file(s)`);
});
