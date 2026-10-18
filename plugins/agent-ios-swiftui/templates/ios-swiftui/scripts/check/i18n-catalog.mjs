#!/usr/bin/env node
/**
 * The String Catalog gate, the iOS side of the kit's check:i18n (AGENTS.md Rules 6 and 7;
 * .claude/rules/ios/strings.md). Reads every tracked *.xcstrings file and the locales in
 * scripts/check/i18n-catalog.json ({"locales": ["en", "id"]}); without that file each catalog is
 * checked against its own source language only.
 *
 *   I1 parity      every key that is translated has every locale; each plural or device variation
 *                  counts. The source language may be absent: the key is then its text.
 *   I2 unfinished  no string unit in state new, needs_review or stale
 *   I3 stale key   no key whose extractionState is stale: no code uses it, so delete it
 *   I4 code/catalog with --stringsdata DIR (the build's .stringsdata files, which the quality gate's
 *                  macOS job passes): a key the code uses is in the catalog that owns that code, and
 *                  an extracted key some code still uses
 *   I5 by name     manual keys (looked up at run time, such as problem.<CODE>) are listed, never
 *                  failed: no build can tell whether one is still used
 *
 * A catalog owns the code of its target: Packages/<P>/Sources/<T>/ for a package catalog, else the
 * catalog's top folder (App/). The table is the catalog's file name.
 *
 *   node scripts/check/i18n-catalog.mjs [--stringsdata DIR]
 *
 * Plain Node ESM, no dependencies, runs on Linux. Exit 0 clean, 1 a finding, 2 unreadable input.
 */
import { execFileSync } from 'node:child_process';
import { existsSync, readdirSync, readFileSync, realpathSync } from 'node:fs';
import { basename, dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

/* The real path: a build records the real path of each source file it read. */
const ROOT = realpathSync(resolve(dirname(fileURLToPath(import.meta.url)), '../..'));
const CONFIG = join(ROOT, 'scripts/check/i18n-catalog.json');
const UNFINISHED = new Set(['new', 'needs_review', 'stale']);

function fail(message) {
  console.error(`i18n-catalog: ${message}`);
  process.exit(2);
}

function readJson(path) {
  try {
    return JSON.parse(readFileSync(path, 'utf8'));
  } catch (err) {
    return fail(`cannot read ${relative(ROOT, path)}: ${err.message}`);
  }
}

/** Repo-relative paths of the tracked catalogs; a folder walk when git cannot answer. */
function catalogs() {
  try {
    const out = execFileSync('git', ['-C', ROOT, 'ls-files', '-z', '--', '*.xcstrings'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    });
    return out.split('\0').filter(Boolean).sort();
  } catch {
    return walk(ROOT, (p) => p.endsWith('.xcstrings')).map((p) => relative(ROOT, p).split(sep).join('/'));
  }
}

function walk(dir, keep, out = []) {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    if (['.git', '.build', 'node_modules', 'DerivedData'].includes(e.name)) continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p, keep, out);
    else if (keep(p)) out.push(p);
  }
  return out.sort();
}

/** Every [path, stringUnit] of one localization, through its variations. */
function* units(localization, path = '') {
  if (localization?.stringUnit) yield [path, localization.stringUnit];
  for (const [kind, cases] of Object.entries(localization?.variations ?? {})) {
    for (const [name, sub] of Object.entries(cases ?? {})) yield* units(sub, `${path}/${kind}.${name}`);
  }
}

/** The folder whose Swift files a catalog's table serves. */
function ownerOf(catalog) {
  const m = catalog.match(/^(.*?\/Sources\/[^/]+)\//);
  return m ? `${m[1]}/` : `${catalog.split('/')[0]}/`;
}

/** Keys the build extracted, by owner folder and table: from every .stringsdata under dir. */
function usedKeys(dir, owners) {
  const used = new Map(owners.map((o) => [o, new Map()]));
  for (const file of walk(resolve(dir), (p) => p.endsWith('.stringsdata'))) {
    const data = readJson(file);
    const recorded = typeof data.source === 'string' ? data.source : '';
    const source = relative(ROOT, existsSync(recorded) ? realpathSync(recorded) : recorded).split(sep).join('/');
    const owner = owners.find((o) => source.startsWith(o));
    if (!owner) continue;
    for (const [table, entries] of Object.entries(data.tables ?? {})) {
      const keys = used.get(owner).get(table) ?? new Map();
      for (const e of entries ?? []) if (!keys.has(e.key)) keys.set(e.key, source);
      used.get(owner).set(table, keys);
    }
  }
  return used;
}

function check(catalog, locales, used) {
  const problems = [];
  const manual = [];
  const data = readJson(join(ROOT, catalog));
  const source = data.sourceLanguage ?? 'en';
  const wanted = locales ?? [source];
  const strings = data.strings ?? {};
  for (const [key, entry] of Object.entries(strings).sort(([a], [b]) => (a < b ? -1 : 1))) {
    if (entry.extractionState === 'stale') {
      problems.push(`I3 "${key}" is stale: no code uses it; delete it from the catalog`);
      continue;
    }
    if (entry.extractionState === 'manual') manual.push(key);
    if (entry.shouldTranslate === false) continue;
    const localizations = entry.localizations ?? {};
    for (const lang of wanted) {
      if (!localizations[lang]) {
        if (lang !== source) problems.push(`I1 "${key}" has no ${lang}`);
        continue;
      }
      for (const [path, unit] of units(localizations[lang])) {
        if (UNFINISHED.has(unit.state)) problems.push(`I2 "${key}" ${lang}${path} is ${unit.state}`);
      }
    }
  }
  if (used) {
    const keys = used.get(ownerOf(catalog))?.get(basename(catalog, '.xcstrings')) ?? new Map();
    for (const [key, file] of [...keys].sort(([a], [b]) => (a < b ? -1 : 1))) {
      if (!(key in strings)) problems.push(`I4 "${key}" is used in ${file} but missing from the catalog`);
    }
    for (const [key, entry] of Object.entries(strings)) {
      const byName = entry.extractionState === 'manual' || entry.extractionState === 'stale';
      if (!byName && !keys.has(key)) {
        /** A literal inside a ternary or a tuple is never extracted, though the code still uses it. */
        problems.push(
          `I4 "${key}" was extracted from code, yet no code uses it now` +
            ' (still in the code, inside a ternary or a tuple? mark it "extractionState": "manual")',
        );
      }
    }
  }
  return { problems, manual };
}

const args = process.argv.slice(2);
let stringsdata = null;
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--stringsdata' && args[i + 1]) stringsdata = args[++i];
  else fail(`unknown argument ${args[i]}; usage: node scripts/check/i18n-catalog.mjs [--stringsdata DIR]`);
}
if (stringsdata && !existsSync(stringsdata)) fail(`--stringsdata ${stringsdata}: no such folder`);

const config = existsSync(CONFIG) ? readJson(CONFIG) : {};
const locales = config.locales ?? null;
if (locales !== null && (!Array.isArray(locales) || !locales.every((l) => typeof l === 'string' && l))) {
  fail('scripts/check/i18n-catalog.json: "locales" must be a list of locale codes');
}
const list = catalogs();
if (list.length === 0) {
  console.log('i18n-catalog: no String Catalog tracked yet; nothing to check');
  process.exit(0);
}
const used = stringsdata ? usedKeys(stringsdata, [...new Set(list.map(ownerOf))]) : null;
let failed = 0;
for (const catalog of list) {
  const { problems, manual } = check(catalog, locales, used);
  for (const p of problems) console.log(`${catalog}: ${p}`);
  if (manual.length) console.log(`${catalog}: I5 ${manual.length} manual key(s) are looked up by name; no build can tell if one is unused`);
  failed += problems.length;
}
const scope = locales ? locales.join(', ') : 'each source language';
if (failed) {
  console.log(`i18n-catalog: ${failed} finding(s) in ${list.length} catalog(s) (locales: ${scope})`);
  process.exit(1);
}
console.log(`i18n-catalog: ${list.length} catalog(s) clean (locales: ${scope}${used ? '; checked against the build' : ''})`);
