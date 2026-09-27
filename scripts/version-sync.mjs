#!/usr/bin/env node
// Keeps versions, the changelog, the marketplace and the release tags in agreement.
//
//   node scripts/version-sync.mjs                  copy each plugin.json description into its
//                                                  marketplace entry (the one derived field), then check
//   node scripts/version-sync.mjs --check          check only; never writes
//   node scripts/version-sync.mjs --check --base <ref>
//                                                  also: every plugin changed since <ref> has a higher
//                                                  version than at <ref>, and CHANGELOG.md changed
//   --root DIR                                     the repository to read (default: this script's)
//
// What agrees with what:
//   - plugin.json `version` is the single source, X.Y.Z. Marketplace entries carry no version
//     (`claude plugin tag` reads plugin.json and accepts that), and their description equals
//     plugin.json's.
//   - Every plugin except agent-core depends on agent-core.
//   - CHANGELOG.md (Keep a Changelog 1.1.0): `## [Unreleased]` first, then repository releases
//     `## [X.Y.Z] - YYYY-MM-DD`, newest first. Every plugin's current version has a
//     `### <plugin> <version>` heading.
//   - Tags: a plugin release is tagged `<plugin>--vX.Y.Z` (claude plugin tag); a local tag newer than
//     plugin.json means the manifest fell behind a release. The reusable workflows are released as
//     `vX.Y.Z`: every template's call to them pins a `# vX.Y.Z` comment that must be a release in
//     CHANGELOG.md (a warning when it is not the newest).
//   - With --base: a change to actions/ or a *-quality-gate.yml workflow also needs a CHANGELOG entry.
//
// Node 20 or newer, no dependencies. Exit 0 clean, 1 out of sync, 2 usage or unreadable input.
import { execFileSync } from 'node:child_process';
import { existsSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const CORE = 'agent-core';
const SEMVER = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;
const CALL = /uses:\s*adhibuchori\/agent-config-kit\/\.github\/workflows\/[A-Za-z0-9._-]+@[0-9a-f]{40}\s*#\s*v(\S+)/g;

function usage(message) {
  console.error(`version-sync: ${message}`);
  console.error('usage: node scripts/version-sync.mjs [--check] [--base <ref>] [--root DIR]');
  process.exit(2);
}

const argv = process.argv.slice(2);
let check = false;
let base = null;
let root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === '--check') check = true;
  else if (argv[i] === '--base') base = argv[++i] ?? usage('--base needs a ref');
  else if (argv[i] === '--root') root = resolve(argv[++i] ?? usage('--root needs a folder'));
  else usage(`unknown argument ${argv[i]}`);
}
if (base !== null && (base === '' || base.startsWith('-'))) usage('--base needs a ref');

const problems = [];
const warnings = [];
const problem = (m) => problems.push(m);

function git(...args) {
  return execFileSync('git', ['-C', root, ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
}

function readJson(path) {
  try {
    return JSON.parse(readFileSync(path, 'utf8'));
  } catch (err) {
    console.error(`version-sync: cannot read ${path}: ${err.message}`);
    process.exit(2);
  }
}

function cmp(a, b) {
  const x = a.split('.').map(Number);
  const y = b.split('.').map(Number);
  for (let i = 0; i < 3; i++) if (x[i] !== y[i]) return x[i] - y[i];
  return 0;
}

// ── Manifests ────────────────────────────────────────────────────────────────────────────────
const marketplacePath = join(root, '.claude-plugin', 'marketplace.json');
if (!existsSync(marketplacePath)) usage(`${marketplacePath} not found`);
const marketplaceRaw = readFileSync(marketplacePath, 'utf8');
const marketplace = readJson(marketplacePath);
const plugins = [];
let rewrote = false;
for (const entry of marketplace.plugins ?? []) {
  const manifestPath = join(root, 'plugins', entry.name, '.claude-plugin', 'plugin.json');
  if (!existsSync(manifestPath)) {
    problem(`marketplace.json: ${entry.name} has no plugins/${entry.name}/.claude-plugin/plugin.json`);
    continue;
  }
  const m = readJson(manifestPath);
  const version = String(m.version ?? '');
  if (!SEMVER.test(version)) problem(`plugins/${entry.name}/.claude-plugin/plugin.json: version "${version}" is not X.Y.Z`);
  if ('version' in entry) problem(`marketplace.json: ${entry.name} carries a version; plugin.json is its only home`);
  if (entry.description !== m.description) {
    if (check) problem(`marketplace.json: ${entry.name} description differs from plugin.json; run: node scripts/version-sync.mjs`);
    else {
      entry.description = m.description;
      rewrote = true;
    }
  }
  if (entry.name !== CORE) {
    const deps = (m.dependencies ?? []).map((d) => (typeof d === 'string' ? d.split('@')[0] : d?.name));
    if (!deps.includes(CORE)) problem(`plugins/${entry.name}/.claude-plugin/plugin.json: dependencies must include "${CORE}"`);
  }
  plugins.push({ name: entry.name, version });
}
if (rewrote) {
  const indent = marketplaceRaw.match(/^[ \t]+(?=")/m)?.[0] ?? '  ';
  writeFileSync(marketplacePath, JSON.stringify(marketplace, null, indent) + (marketplaceRaw.endsWith('\n') ? '\n' : ''));
  console.log('version-sync: copied plugin.json descriptions into marketplace.json');
}

// ── CHANGELOG.md ─────────────────────────────────────────────────────────────────────────────
const changelogPath = join(root, 'CHANGELOG.md');
const releases = [];
if (!existsSync(changelogPath)) {
  problem('CHANGELOG.md: missing');
} else {
  const lines = readFileSync(changelogPath, 'utf8').split('\n');
  const h2 = lines.map((l, i) => ({ l, i })).filter(({ l }) => /^## /.test(l));
  if (!h2.length || !/^## \[Unreleased\]\s*$/.test(h2[0].l)) problem('CHANGELOG.md: the first "## " heading must be "## [Unreleased]"');
  for (const { l, i } of h2.slice(1)) {
    const m = l.match(/^## \[(\d+\.\d+\.\d+)\] - (\d{4}-\d{2}-\d{2})\s*$/);
    if (!m) {
      problem(`CHANGELOG.md:${i + 1}: "${l}" is not "## [X.Y.Z] - YYYY-MM-DD"`);
      continue;
    }
    const d = new Date(`${m[2]}T00:00:00Z`);
    if (Number.isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== m[2]) problem(`CHANGELOG.md:${i + 1}: ${m[2]} is not a real date`);
    releases.push({ version: m[1], date: m[2], line: i + 1 });
  }
  for (let i = 1; i < releases.length; i++) {
    if (cmp(releases[i - 1].version, releases[i].version) <= 0) {
      problem(`CHANGELOG.md:${releases[i].line}: releases must be newest first (${releases[i - 1].version} above ${releases[i].version})`);
    }
  }
  const text = lines.join('\n');
  for (const p of plugins) {
    const re = new RegExp(`^### ${p.name.replace(/[-]/g, '\\-')} ${p.version.replace(/\./g, '\\.')}\\s*$`, 'm');
    if (SEMVER.test(p.version) && !re.test(text)) problem(`CHANGELOG.md: no "### ${p.name} ${p.version}" heading for the current version`);
  }
}

// ── Tags ─────────────────────────────────────────────────────────────────────────────────────
let tags = [];
try {
  tags = git('tag', '--list').split('\n').filter(Boolean);
} catch {
  tags = [];
}
for (const p of plugins) {
  for (const t of tags) {
    const m = t.match(new RegExp(`^${p.name}--v(\\d+\\.\\d+\\.\\d+)$`));
    if (m && SEMVER.test(p.version) && cmp(m[1], p.version) > 0) {
      problem(`plugins/${p.name}: tag ${t} is newer than plugin.json's ${p.version}`);
    }
  }
}

// The version comment of every call to this repository's reusable workflows is a release.
const releaseSet = new Set(releases.map((r) => r.version));
const newest = releases[0]?.version;
const pluginsDir = join(root, 'plugins');
if (existsSync(pluginsDir)) {
  for (const p of readdirSync(pluginsDir)) {
    const tdir = join(pluginsDir, p, 'templates');
    if (!existsSync(tdir)) continue;
    for (const stack of readdirSync(tdir)) {
      const wdir = join(tdir, stack, '.github', 'workflows');
      if (!existsSync(wdir)) continue;
      for (const f of readdirSync(wdir).filter((f) => /\.ya?ml$/.test(f))) {
        const rel = `plugins/${p}/templates/${stack}/.github/workflows/${f}`;
        for (const m of readFileSync(join(wdir, f), 'utf8').matchAll(CALL)) {
          if (!releaseSet.has(m[1])) problem(`${rel}: pins # v${m[1]}, which is not a release in CHANGELOG.md`);
          else if (m[1] !== newest) warnings.push(`${rel}: pins # v${m[1]}; the newest release is v${newest}`);
        }
      }
    }
  }
}

// ── Against the base ─────────────────────────────────────────────────────────────────────────
if (base !== null) {
  let changed;
  try {
    git('rev-parse', '--verify', '--quiet', `${base}^{commit}`);
    changed = git('diff', '--name-only', `${base}...HEAD`).split('\n').filter(Boolean);
  } catch {
    console.error(`version-sync: cannot diff against ${base} (fetch it, or check out with fetch-depth: 0)`);
    process.exit(2);
  }
  let needsChangelog = false;
  for (const p of plugins) {
    const prefix = `plugins/${p.name}/`;
    const touched = changed.filter((f) => f.startsWith(prefix));
    if (!touched.length) continue;
    needsChangelog = true;
    let before = null;
    try {
      before = JSON.parse(git('show', `${base}:${prefix}.claude-plugin/plugin.json`)).version;
    } catch {
      continue; // new since base: its first version needs no bump
    }
    if (SEMVER.test(String(before)) && SEMVER.test(p.version) && cmp(p.version, before) <= 0) {
      problem(`plugins/${p.name}: ${touched.length} file(s) changed since ${base} but the version is still ${p.version} (was ${before}); bump it in plugin.json`);
    }
  }
  if (changed.some((f) => f.startsWith('actions/') || /^\.github\/workflows\/[^/]+-quality-gate\.yml$/.test(f))) needsChangelog = true;
  if (needsChangelog && !changed.includes('CHANGELOG.md')) {
    problem(`CHANGELOG.md: a plugin, an action or a reusable workflow changed since ${base}, but the changelog did not`);
  }
}

for (const w of warnings) console.log(`WARN: ${w}`);
if (problems.length) {
  for (const m of problems) console.log(`FAIL: ${m}`);
  console.log(`version-sync: ${plugins.length} plugin(s), ${problems.length} problem(s)`);
  process.exit(1);
}
console.log(`version-sync: ${plugins.length} plugin(s) at ${plugins.map((p) => `${p.name} ${p.version}`).join(', ')}; in sync`);
