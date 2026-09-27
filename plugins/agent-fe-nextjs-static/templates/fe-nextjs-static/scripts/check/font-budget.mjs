#!/usr/bin/env node
// Font budget: at most fonts.maxFamilies families (default 2), self-hosted (no third-party font
// requests), with the file count, total size, static weights and formats kept in check.
//   --source (or no build): reads next/font imports, localFont() calls and @font-face in the source.
//   with a build: reads the @font-face rules of the built CSS and the files they load.
// Rule: .claude/rules/web/performance.md. Budgets: fonts.* in scripts/check/site.config.json.
//
//   node scripts/check/font-budget.mjs [--source] [--dir out] [--root .] [--config FILE]
import { existsSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import {
  UsageError,
  filesUnder,
  openSite,
  run,
  sourceFiles,
  stripComments,
  toPosix,
} from './lib/site.mjs';

const THIRD_PARTY =
  /\b(fonts\.googleapis\.com|fonts\.gstatic\.com|use\.typekit\.net|fonts\.bunny\.net|use\.fontawesome\.com)\b/;

/** A family name without quotes, next/font hashes or the generated fallback suffix. */
function family(name) {
  return name
    .trim()
    .replace(/^['"]|['"]$/g, '')
    .replace(/\s+Fallback$/i, '')
    .replace(/^__(.+?)_[0-9a-f]{5,}$/i, '$1')
    .replace(/_Fallback$/i, '')
    .replace(/_/g, ' ')
    .trim();
}

function fontFaces(css) {
  return [...stripComments(css).matchAll(/@font-face\s*{([^}]*)}/g)].map((m) => {
    const body = m[1];
    const get = (p) =>
      (body.match(new RegExp(`(?:^|;)\\s*${p}\\s*:\\s*([^;]+)`, 'i')) || [])[1]?.trim() || '';
    const urls = [...get('src').matchAll(/url\(\s*['"]?([^'")]+)['"]?\s*\)/g)].map((u) => u[1]);
    return {
      family: family(get('font-family')),
      weight: get('font-weight') || '400',
      display: get('font-display'),
      urls,
    };
  });
}

function fromBuild(site, root, cfg, report) {
  const cssRoots =
    site.mode === 'export' || site.pagesDir !== join(root, '.next/server/app')
      ? [site.pagesDir]
      : [join(root, '.next/static')];
  const cssFiles = cssRoots.flatMap((r) => filesUnder(r).filter((f) => f.endsWith('.css')));
  const families = new Map();
  const files = new Map();
  for (const css of cssFiles) {
    for (const face of fontFaces(readFileSync(css, 'utf8'))) {
      if (!face.urls.length) continue; // a local() fallback face downloads nothing
      const entry = families.get(face.family) || {
        weights: new Set(),
        where: toPosix(relative(root, css)),
      };
      entry.weights.add(face.weight);
      families.set(face.family, entry);
      if (!face.display || face.display === 'block') {
        report.warn(
          toPosix(relative(root, css)),
          `@font-face "${face.family}" has font-display ${face.display || 'unset'}: text stays invisible while it loads (use swap or optional)`,
        );
      }
      for (const u of face.urls) {
        if (/^(https?:)?\/\//.test(u)) {
          report.error(
            toPosix(relative(root, css)),
            `@font-face "${face.family}" loads ${u} from another host: self-host it with next/font`,
          );
          continue;
        }
        const clean = u.split(/[?#]/)[0];
        const file = clean.startsWith('/') ? site.resolvePath(clean) : join(dirname(css), clean);
        if (file && existsSync(file)) files.set(file, statSync(file).size);
        else
          report.error(
            toPosix(relative(root, css)),
            `@font-face "${face.family}" points at ${u}, which is not in the build`,
          );
      }
    }
  }
  return { families, files, source: `${cssFiles.length} built stylesheet(s)` };
}

function fromSource(root, report) {
  const families = new Map();
  const add = (name, where, weights = []) => {
    const e = families.get(name) || { weights: new Set(), where };
    weights.forEach((w) => e.weights.add(w));
    families.set(name, e);
  };
  for (const f of sourceFiles(root)) {
    const rel = toPosix(relative(root, f));
    const src = stripComments(readFileSync(f, 'utf8'));
    if (THIRD_PARTY.test(src))
      report.error(rel, 'requests fonts from a third-party host: self-host them with next/font');
    for (const m of src.matchAll(/import\s*{([^}]*)}\s*from\s*['"]next\/font\/google['"]/g)) {
      for (const name of m[1]
        .split(',')
        .map((s) => s.trim().split(/\s+as\s+/)[0])
        .filter(Boolean)) {
        const call = src.match(new RegExp(`\\b${name}\\s*\\(\\s*{([\\s\\S]*?)}\\s*\\)`));
        const weights = call
          ? [
              ...(call[1].match(/weight\s*:\s*(\[[^\]]*\]|['"][^'"]*['"])/)?.[1] || '').matchAll(
                /['"]([^'"]+)['"]/g,
              ),
            ].map((w) => w[1])
          : [];
        add(family(name), rel, weights);
      }
    }
    for (const m of src.matchAll(/(?:const|let|var)\s+(\w+)\s*=\s*localFont\s*\(/g))
      add(`local:${m[1]}`, rel);
    if (f.endsWith('.css') || f.endsWith('.scss')) {
      for (const face of fontFaces(src)) if (face.urls.length) add(face.family, rel, [face.weight]);
    }
  }
  return { families, files: new Map(), source: 'source files' };
}

run(
  'font-budget',
  ({ args, root, cfg, report }) => {
    const { maxFamilies, maxFiles, maxTotalKB } = cfg.fonts;
    let site = null;
    if (!args.source) {
      try {
        site = openSite(root, cfg, args.dir);
      } catch (e) {
        if (!(e instanceof UsageError) || args.dir) throw e;
      }
    }
    const { families, files, source } = site
      ? fromBuild(site, root, cfg, report)
      : fromSource(root, report);

    if (families.size > maxFamilies) {
      const list = [...families.entries()]
        .map(([n, e]) => `${n.replace(/^local:/, 'localFont ')} (${e.where})`)
        .join(', ');
      report.error('fonts', `${families.size} font families, budget ${maxFamilies}: ${list}`);
    }
    for (const [name, e] of families) {
      const statics = [...e.weights].filter((w) => !/\s/.test(w.trim()));
      if (statics.length > 4)
        report.warn(
          e.where,
          `${name}: ${statics.length} static weights; a variable font or fewer weights loads less`,
        );
    }
    if (files.size) {
      const totalKB = Math.ceil([...files.values()].reduce((a, b) => a + b, 0) / 1024);
      if (files.size > maxFiles)
        report.warn(
          'fonts',
          `${files.size} font files in the build (budget ${maxFiles}); unicode-range subsets load only when used, but check the list`,
        );
      if (totalKB > maxTotalKB)
        report.warn('fonts', `${totalKB} KB of font files in the build (budget ${maxTotalKB} KB)`);
      for (const f of files.keys()) {
        if (!/\.woff2$/i.test(f))
          report.warn(toPosix(relative(root, f)), 'is not WOFF2, the smallest web font format');
      }
    }
    return report.finish(
      `${families.size} famil${families.size === 1 ? 'y' : 'ies'} from ${source}`,
    );
  },
  { switches: ['source'] },
);
