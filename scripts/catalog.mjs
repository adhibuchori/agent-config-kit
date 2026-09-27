#!/usr/bin/env node
// Generates the plugin catalog in the READMEs and enforces the repository's layout invariants.
//
//   node scripts/catalog.mjs            rewrite the generated blocks, then check
//   node scripts/catalog.mjs --check    check only; never writes (CI runs this)
//   --root DIR                          the repository to read (default: this script's repository)
//
// Generated blocks (the text between the markers is replaced whole):
//   <!-- catalog:start --> ... <!-- catalog:end -->  README.md and README.id.md: every plugin;
//                                                    plugins/<p>/README.md: that plugin only.
//                                                    One row per component: Component, Kind,
//                                                    What it does, How to use, Why it helps, Docs.
//                                                    A component is a hook, command, agent or skill,
//                                                    or a workflow a plugin's setup installs
//                                                    (templates/<stack>/.github/workflows/*.y*ml).
//                                                    README.id.md gets the same table in Indonesian.
//   <!-- install:start --> ... <!-- install:end -->  README.md: docs/install-block.md, verbatim;
//                                                    README.id.md: docs/install-block.id.md, verbatim;
//                                                    plugins/<p>/README.md: docs/install-block.plugin.md
//                                                    with that plugin's own name and install lines.
//   <!-- files:start --> ... <!-- files:end -->      README.md and README.id.md (optional): every file
//                                                    each plugin's setup installs, when, and what it is.
// "What it does" is the description in a command's, agent's or skill's frontmatter, and for a hook or
// a workflow the first sentence under "## What it does" in its docs page (README.id.md:
// docs/catalog.json).
// "How to use" and "Why it helps" come from docs/catalog.json, one entry per component, keyed by its
// docs page (<plugin>/<page name>). "What it is" for an installed file is its first Markdown heading
// or its first comment sentence, else the entry for its name or path in docs/catalog.json "files".
//
// Invariants (--check, and after a rewrite):
//   - README.md has both marker pairs; every plugins/<p>/README.md exists with the install markers;
//     every generated block is current.
//   - Every component (hook script wired in hooks/hooks.json, command, agent, skill, template
//     workflow) has a page at docs/<plugin>/<name>.md (<name>.<kind>.md when two kinds share a name;
//     a workflow alone takes <name>.workflow.md when it shares its name with another component), and
//     every page in docs/<plugin>/ belongs to a component. lib.sh and setup-check.sh are not
//     components.
//   - plugins/agent-core/commands/help.md names every command of every plugin as /<plugin>:<command>.
//   - marketplace.json: one entry per plugins/<p>, sorted by name, names ^[a-z0-9][a-z0-9-]{1,63}$,
//     source ./plugins/<name>, no version, a description of 10-2000 characters identical to the
//     plugin.json one.
//   - No hidden or bidirectional Unicode in the manifests, hooks.json or component markdown.
//   - Every plugins/<p>/scripts/lib.sh has the same bytes as agent-core's.
//   - Templates (plugins/<p>/templates/<stack>/, _kit/ aside): no package.json, no file named
//     .gitignore, nothing under .claude/{hooks,commands,agents,skills}/, no symlink, no real .env
//     file, CLAUDE.md and AGENTS.md only as *.starter; a .claude/settings.json holds only
//     $schema, permissions, sandbox, env, extraKnownMarketplaces and enabledPlugins (never hooks);
//     a destination path shipped by two plugins has the same bytes, unless it is
//     .claude/settings.json (merged) or the two plugins name each other in conflictsWith.
//   - plugins/*/bin/* and plugins/*/scripts/*.sh are mode 100755 in the git index (on disk when
//     not yet tracked).
//   - Hook scripts, bin/, libexec/ and hooks/ never run a download tool (curl, wget, npx, bunx,
//     uvx, pipx, pnpx, pip/npm/bun install, uv tool install, go install).
//   - docs/catalog.json has an entry (use, why, id.what, id.use, id.why) for every component and none
//     for a component that does not exist; every installed file has a "What it is".
//   - A template settings.json never allows a bare runner (`bun run`, `npm run`, `uv run`, `npx`,
//     `docker compose`, …): each would run any code without a prompt. Allow named scripts instead.
//   - The commands that commit, push, merge, post to GitHub or install files are user-only
//     (`disable-model-invocation: true`), and so is every skill that may download code.
//
// Node 20 or newer, no dependencies. Exit 0 clean, 1 stale or invalid, 2 usage or unreadable input.
import { execFileSync } from 'node:child_process';
import { existsSync, lstatSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const CORE = 'agent-core';
const NOT_COMPONENTS = new Set(['lib', 'setup-check']);
const NAME_RE = /^[a-z0-9][a-z0-9-]{1,63}$/;
const SETTINGS_KEYS = new Set(['$schema', 'permissions', 'sandbox', 'env', 'extraKnownMarketplaces', 'enabledPlugins']);
// Zero-width, bidirectional controls, word joiners, BOM, soft hyphen, and C0/C1 controls other than
// tab, newline and carriage return.
const HIDDEN = /[\u00AD\u200B-\u200F\u202A-\u202E\u2060-\u2064\u2066-\u2069\uFEFF\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]/u;
const DOWNLOAD = /(?:^|[;&|(`]|\$\()\s*(?:sudo\s+)?(?:curl|wget|npx|bunx|uvx|pipx|pnpx|pip3?\s+install|npm\s+(?:install|i|ci)|uv\s+tool\s+install|bun\s+(?:add|install)|go\s+install)(?:\s|$)/;
const DOWNLOAD_EXEC = /\[\s*["'](?:curl|wget|npx|bunx|uvx|pipx|pnpx)["']/;
const MARK = {
  catalog: ['<!-- catalog:start -->', '<!-- catalog:end -->'],
  install: ['<!-- install:start -->', '<!-- install:end -->'],
  files: ['<!-- files:start -->', '<!-- files:end -->'],
};
// A permission that lets Claude run any code without a prompt.
const BROAD_ALLOW = /^Bash\((?:(?:npm|pnpm|yarn|bun) run|uv run|uvx|npx|bunx|pnpx|pnpm dlx|yarn dlx|docker(?: compose)?|node|bun|python3?|bash|sh|eval)(?::\*|\s\*)?\)$/;
// Commands a user must type themselves: they commit, push, merge, post to GitHub or install files.
const USER_ONLY = new Set(['setup', 'sync', 'branch-cleanup', 'checkpoint', 'commit', 'create-pr', 'merge-pr',
  'promote', 'resolve-pr-review', 'ship', 'promote-deploy', 'verify-deploy']);
const GENERATED_NOTE = '<!-- Generated by scripts/catalog.mjs from the plugin manifests, docs/ and docs/catalog.json. Edit those, then run it. -->';

function usage(message) {
  console.error(`catalog: ${message}`);
  console.error('usage: node scripts/catalog.mjs [--check] [--root DIR]');
  process.exit(2);
}

const argv = process.argv.slice(2);
let check = false;
let root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === '--check') check = true;
  else if (argv[i] === '--root') root = resolve(argv[++i] ?? usage('--root needs a folder'));
  else usage(`unknown argument ${argv[i]}`);
}

const problems = [];
const problem = (msg) => problems.push(msg);
const rel = (p) => relative(root, p).split(sep).join('/');
const read = (p) => readFileSync(p, 'utf8');

function readJson(p) {
  try {
    return JSON.parse(read(p));
  } catch (err) {
    console.error(`catalog: cannot read ${rel(p)}: ${err.message}`);
    process.exit(2);
  }
}

function walk(dir, out = []) {
  if (!existsSync(dir)) return out;
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else out.push(p);
  }
  return out;
}

// The frontmatter's top-level keys: plain, quoted, or a block scalar (| or >) on indented lines.
function frontmatter(text) {
  const lines = text.split('\n');
  if (lines[0].trim() !== '---') return null;
  const end = lines.findIndex((l, i) => i > 0 && l.trim() === '---');
  if (end < 0) return null;
  const out = {};
  for (let i = 1; i < end; i++) {
    const m = lines[i].match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    if (!m) continue;
    let value = m[2].trim();
    if (/^[|>][+-]?$/.test(value)) {
      const block = [];
      while (i + 1 < end && (/^\s/.test(lines[i + 1]) || lines[i + 1].trim() === '')) block.push(lines[++i].trim());
      value = block.join(' ').trim();
    } else if (/^".*"$/.test(value)) {
      value = value.slice(1, -1).replace(/\\"/g, '"');
    } else if (/^'.*'$/.test(value)) {
      value = value.slice(1, -1).replace(/''/g, "'");
    }
    out[m[1]] = value;
  }
  return out;
}

function firstSentence(text) {
  const flat = text.replace(/\s+/g, ' ').trim();
  const m = flat.match(/^(.+?[.!?])(?:\s|$)/);
  return m ? m[1] : flat;
}

// The first paragraph under "## What it does" in a hook's docs page.
function whatItDoes(page) {
  if (!existsSync(page)) return '';
  const lines = read(page).split('\n');
  const at = lines.findIndex((l) => /^##\s+What it does\s*$/.test(l));
  if (at < 0) return '';
  const para = [];
  for (let i = at + 1; i < lines.length; i++) {
    if (/^#/.test(lines[i])) break;
    if (lines[i].trim() === '') {
      if (para.length) break;
      continue;
    }
    para.push(lines[i]);
  }
  return firstSentence(para.join(' '));
}

// Table cells: one line, pipes escaped, and < > & as entities so a word like <scope> is shown, not
// swallowed as an HTML tag.
const cell = (s) =>
  String(s ?? '')
    .replace(/\s+/g, ' ')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/\|/g, '\\|')
    .trim();

// A setup.json install glob as a regular expression: ** crosses folders, * and ? do not.
const globRe = (g) => new RegExp(`^${g.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*\*\//g, '(?:.*/)?').replace(/\*\*/g, '.*').replace(/\*/g, '[^/]*').replace(/\?/g, '[^/]')}$`);

// ── Manifests ────────────────────────────────────────────────────────────────────────────────
const marketplacePath = join(root, '.claude-plugin', 'marketplace.json');
if (!existsSync(marketplacePath)) usage(`${rel(marketplacePath)} not found; is --root a checkout of agent-config-kit?`);
const marketplaceText = read(marketplacePath);
const marketplace = readJson(marketplacePath);
if (HIDDEN.test(marketplaceText)) problem('.claude-plugin/marketplace.json: hidden or bidirectional Unicode');
const entries = Array.isArray(marketplace.plugins) ? marketplace.plugins : [];
const names = entries.map((e) => e.name);
const sorted = [...names].sort();
if (names.join('\n') !== sorted.join('\n')) problem(`marketplace.json: plugins are not sorted by name (${names.join(', ')})`);
const dirs = existsSync(join(root, 'plugins'))
  ? readdirSync(join(root, 'plugins'), { withFileTypes: true }).filter((e) => e.isDirectory()).map((e) => e.name).sort()
  : [];
for (const d of dirs) if (!names.includes(d)) problem(`plugins/${d}: no marketplace.json entry`);

const plugins = [];
for (const entry of entries) {
  const name = entry.name;
  if (!NAME_RE.test(name ?? '')) problem(`marketplace.json: plugin name "${name}" does not match ${NAME_RE}`);
  if (!dirs.includes(name)) {
    problem(`marketplace.json: "${name}" has no plugins/${name} folder`);
    continue;
  }
  if (entry.source !== `./plugins/${name}`) problem(`marketplace.json: ${name} source is ${JSON.stringify(entry.source)}, expected "./plugins/${name}"`);
  if ('version' in entry) problem(`marketplace.json: ${name} carries a version; plugin.json is the only place for it`);
  const dir = join(root, 'plugins', name);
  const manifestPath = join(dir, '.claude-plugin', 'plugin.json');
  if (!existsSync(manifestPath)) {
    problem(`plugins/${name}: no .claude-plugin/plugin.json`);
    continue;
  }
  const manifestText = read(manifestPath);
  const manifest = readJson(manifestPath);
  if (HIDDEN.test(manifestText)) problem(`${rel(manifestPath)}: hidden or bidirectional Unicode`);
  if (manifest.name !== name) problem(`${rel(manifestPath)}: name "${manifest.name}" is not "${name}"`);
  const desc = manifest.description ?? '';
  if (desc.length < 10 || desc.length > 2000) problem(`${rel(manifestPath)}: description is ${desc.length} characters, not 10-2000`);
  if (entry.description !== desc) problem(`marketplace.json: ${name} description differs from its plugin.json (node scripts/version-sync.mjs copies it)`);
  plugins.push({ name, dir, manifest });
}
// agent-core first, then the others in marketplace order.
plugins.sort((a, b) => (a.name === CORE ? -1 : b.name === CORE ? 1 : 0));

// ── Components ───────────────────────────────────────────────────────────────────────────────
function checkHidden(path, text) {
  if (HIDDEN.test(text)) problem(`${rel(path)}: hidden or bidirectional Unicode`);
}

for (const p of plugins) {
  const comps = [];
  const hooksPath = join(p.dir, 'hooks', 'hooks.json');
  if (existsSync(hooksPath)) {
    const text = read(hooksPath);
    checkHidden(hooksPath, text);
    const hooks = readJson(hooksPath).hooks ?? {};
    const seen = new Map();
    for (const [event, groups] of Object.entries(hooks)) {
      for (const group of groups ?? []) {
        for (const h of group.hooks ?? []) {
          for (const m of String(h.command ?? '').matchAll(/\$\{CLAUDE_PLUGIN_ROOT\}\/scripts\/([A-Za-z0-9._-]+)\.sh/g)) {
            if (NOT_COMPONENTS.has(m[1])) continue;
            const on = group.matcher ? `${event} on \`${group.matcher}\`` : event;
            if (!seen.has(m[1])) {
              seen.set(m[1], [on]);
              comps.push({ kind: 'hook', name: m[1], invoke: m[1] });
            } else if (!seen.get(m[1]).includes(on)) seen.get(m[1]).push(on);
          }
        }
      }
    }
    for (const c of comps) c.on = seen.get(c.name).join('; ');
  }
  for (const f of walk(join(p.dir, 'commands')).filter((f) => f.endsWith('.md')).sort()) {
    const text = read(f);
    checkHidden(f, text);
    const name = relative(join(p.dir, 'commands'), f).split(sep).join('/').replace(/\.md$/, '');
    const fm = frontmatter(text) ?? {};
    const userOnly = fm['disable-model-invocation'] === 'true';
    if (USER_ONLY.has(name) && !userOnly) problem(`${rel(f)}: ${name} commits, pushes, merges or installs files, so it needs disable-model-invocation: true`);
    comps.push({ kind: 'command', name, invoke: `/${p.name}:${name.replace(/\//g, ':')}`, desc: fm.description ?? '', userOnly });
  }
  const agentsDir = join(p.dir, 'agents');
  if (existsSync(agentsDir)) {
    for (const f of readdirSync(agentsDir).filter((f) => f.endsWith('.md')).sort()) {
      const text = read(join(agentsDir, f));
      checkHidden(join(agentsDir, f), text);
      const fm = frontmatter(text) ?? {};
      const name = fm.name || f.replace(/\.md$/, '');
      comps.push({ kind: 'agent', name, invoke: `${p.name}:${name}`, desc: fm.description ?? '' });
    }
  }
  const skillsDir = join(p.dir, 'skills');
  if (existsSync(skillsDir)) {
    for (const d of readdirSync(skillsDir, { withFileTypes: true }).filter((e) => e.isDirectory()).map((e) => e.name).sort()) {
      const f = join(skillsDir, d, 'SKILL.md');
      if (!existsSync(f)) continue;
      const text = read(f);
      checkHidden(f, text);
      const fm = frontmatter(text) ?? {};
      const name = fm.name || d;
      const userOnly = fm['disable-model-invocation'] === 'true';
      if (/\b(?:bunx|npx|pnpx|uvx|pnpm dlx|yarn dlx)\s/.test(text) && !userOnly) problem(`${rel(f)}: a skill that may download code must be user-only (disable-model-invocation: true)`);
      comps.push({ kind: 'skill', name, invoke: `${p.name}:${name}`, desc: fm.description ?? '', userOnly });
    }
  }
  // The workflows setup installs: every templates/<stack>/.github/workflows/*.y*ml. One is optional
  // when a setup question gates it.
  const templatesDir = join(p.dir, 'templates');
  const workflows = [];
  if (existsSync(templatesDir)) {
    for (const stack of readdirSync(templatesDir, { withFileTypes: true }).filter((e) => e.isDirectory()).map((e) => e.name).sort()) {
      const wdir = join(templatesDir, stack, '.github', 'workflows');
      if (!existsSync(wdir)) continue;
      const setupPath = join(templatesDir, stack, '_kit', 'setup.json');
      const questions = existsSync(setupPath) ? readJson(setupPath).questions ?? [] : [];
      for (const f of readdirSync(wdir).filter((f) => /\.ya?ml$/.test(f)).sort()) {
        const dest = `.github/workflows/${f}`;
        const optional = questions.some((q) => Object.values(q.install ?? {}).flat().some((g) => globRe(g).test(dest)));
        workflows.push({ kind: 'workflow', name: f.replace(/\.ya?ml$/, ''), invoke: dest, optional });
      }
    }
  }
  // Docs pages: <name>.md, or <name>.<kind>.md when two kinds in one plugin share a name. A workflow
  // that shares its name with another component takes <name>.workflow.md and leaves the other's page
  // where it is.
  const kindsByName = new Map();
  for (const c of comps) kindsByName.set(c.name, (kindsByName.get(c.name) ?? 0) + 1);
  for (const c of comps) c.page = `docs/${p.name}/${kindsByName.get(c.name) > 1 ? `${c.name}.${c.kind}` : c.name}.md`;
  for (const w of workflows) w.page = `docs/${p.name}/${kindsByName.has(w.name) ? `${w.name}.workflow` : w.name}.md`;
  comps.push(...workflows);
  for (const c of comps) if (c.kind === 'hook' || c.kind === 'workflow') c.desc = whatItDoes(join(root, c.page));
  p.comps = comps;
}

// ── Docs pages both ways ─────────────────────────────────────────────────────────────────────
for (const p of plugins) {
  const expected = new Set(p.comps.map((c) => c.page));
  for (const c of p.comps) if (!existsSync(join(root, c.page))) problem(`${c.page}: missing (the page for ${c.kind} ${c.invoke})`);
  for (const f of walk(join(root, 'docs', p.name)).filter((f) => f.endsWith('.md'))) {
    const r = rel(f);
    if (r === `docs/${p.name}/README.md`) continue;
    if (!expected.has(r)) problem(`${r}: no component of ${p.name} has this page`);
  }
  for (const c of p.comps.filter((c) => c.kind === 'hook' || c.kind === 'workflow')) {
    if (existsSync(join(root, c.page)) && !c.desc) problem(`${c.page}: no sentence under "## What it does"`);
  }
}

// ── docs/catalog.json: how to use, why it helps, and the Indonesian texts ──────────────────────
const notesPath = join(root, 'docs', 'catalog.json');
const notes = existsSync(notesPath) ? readJson(notesPath) : null;
const noteOf = (c) => notes?.components?.[c.page.replace(/^docs\//, '').replace(/\.md$/, '')] ?? null;
if (!notes) problem('docs/catalog.json: missing (how to use and why it helps, for every component)');
else {
  checkHidden(notesPath, read(notesPath));
  const known = new Set();
  const str = (v) => typeof v === 'string' && v.trim() !== '';
  for (const p of plugins) {
    for (const c of p.comps) {
      const key = c.page.replace(/^docs\//, '').replace(/\.md$/, '');
      known.add(key);
      const n = noteOf(c);
      if (!n) problem(`docs/catalog.json: no entry "${key}" (how to use and why it helps, for ${c.kind} ${c.invoke})`);
      else if (![n.use, n.why, n.id?.what, n.id?.use, n.id?.why].every(str)) problem(`docs/catalog.json: "${key}" needs use, why, id.what, id.use and id.why`);
    }
  }
  for (const key of Object.keys(notes.components ?? {})) {
    if (!known.has(key)) problem(`docs/catalog.json: "${key}" names no component`);
  }
}

// ── The router names every command ───────────────────────────────────────────────────────────
const helpPath = join(root, 'plugins', CORE, 'commands', 'help.md');
if (plugins.some((p) => p.name === CORE)) {
  if (!existsSync(helpPath)) problem(`plugins/${CORE}/commands/help.md: missing (the router must name every command)`);
  else {
    const help = read(helpPath);
    for (const p of plugins) {
      for (const c of p.comps.filter((c) => c.kind === 'command')) {
        const re = new RegExp(`${c.invoke.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}(?![A-Za-z0-9:_-])`);
        if (!re.test(help)) problem(`plugins/${CORE}/commands/help.md: does not name ${c.invoke}`);
      }
    }
  }
}

// ── lib.sh copies ────────────────────────────────────────────────────────────────────────────
const coreLib = join(root, 'plugins', CORE, 'scripts', 'lib.sh');
for (const p of plugins) {
  const lib = join(p.dir, 'scripts', 'lib.sh');
  if (p.name === CORE || !existsSync(lib)) continue;
  if (!existsSync(coreLib)) problem(`${rel(lib)}: agent-core has no scripts/lib.sh to copy`);
  else if (!readFileSync(lib).equals(readFileSync(coreLib))) problem(`${rel(lib)}: differs from plugins/${CORE}/scripts/lib.sh (it must be an exact copy)`);
}

// ── Templates ────────────────────────────────────────────────────────────────────────────────
const destinations = new Map(); // dest path -> [{plugin, file}]
const conflicts = new Map(); // plugin -> Set(conflictsWith)
const stacks = new Map(); // plugin -> { dir, setup }
for (const p of plugins) {
  const tdir = join(p.dir, 'templates');
  if (!existsSync(tdir)) continue;
  for (const stack of readdirSync(tdir, { withFileTypes: true }).filter((e) => e.isDirectory())) {
    const sdir = join(tdir, stack.name);
    const setupPath = join(sdir, '_kit', 'setup.json');
    if (existsSync(setupPath)) {
      const setup = readJson(setupPath);
      conflicts.set(p.name, new Set(setup.conflictsWith ?? []));
      stacks.set(p.name, { dir: sdir, setup });
    }
    const stackWalk = (dir) => {
      for (const e of readdirSync(dir, { withFileTypes: true })) {
        const full = join(dir, e.name);
        const dest = relative(sdir, full).split(sep).join('/');
        if (dest === '_kit' || dest.startsWith('_kit/')) continue;
        if (lstatSync(full).isSymbolicLink()) {
          problem(`${rel(full)}: a symlink in templates (setup refuses them)`);
          continue;
        }
        if (e.isDirectory()) {
          if (/^\.claude\/(hooks|commands|agents|skills)$/.test(dest)) problem(`${rel(full)}: plugin components never ship as template files (they would run twice)`);
          stackWalk(full);
          continue;
        }
        const base = e.name;
        if (base === 'package.json') problem(`${rel(full)}: no package.json in templates; scripts go in _kit/setup.json packageScripts`);
        if (base === '.gitignore') problem(`${rel(full)}: no .gitignore in templates; lines go in _kit/setup.json gitignore`);
        if (/^\.env($|\.)/.test(base) && !/\.example$/.test(base)) problem(`${rel(full)}: a real .env file in templates (only *.example)`);
        if (base === 'CLAUDE.md' || base === 'AGENTS.md') problem(`${rel(full)}: ship it as ${base}.starter, or it loads as instructions in this repository`);
        if (dest === '.claude/settings.json') {
          let settings = {};
          try {
            settings = JSON.parse(read(full));
          } catch {
            problem(`${rel(full)}: not valid JSON`);
          }
          for (const k of Object.keys(settings)) {
            if (!SETTINGS_KEYS.has(k)) problem(`${rel(full)}: top-level key "${k}" is not allowed in a template settings.json${k === 'hooks' ? ' (hooks live in the plugin; this would wire them twice)' : ''}`);
          }
          for (const rule of settings.permissions?.allow ?? []) {
            if (BROAD_ALLOW.test(String(rule))) problem(`${rel(full)}: allow rule ${rule} runs any code without a prompt; allow named scripts, or move it to ask`);
          }
        }
        const target = dest.endsWith('.starter') ? dest.slice(0, -'.starter'.length) : dest;
        if (!destinations.has(target)) destinations.set(target, []);
        destinations.get(target).push({ plugin: p.name, file: full });
      }
    };
    stackWalk(sdir);
  }
}
for (const [dest, list] of destinations) {
  if (dest === '.claude/settings.json' || list.length < 2) continue;
  for (let i = 1; i < list.length; i++) {
    const a = list[0];
    const b = list[i];
    if (a.plugin === b.plugin) continue;
    const named = conflicts.get(a.plugin)?.has(b.plugin) && conflicts.get(b.plugin)?.has(a.plugin);
    if (!named && !readFileSync(a.file).equals(readFileSync(b.file))) {
      problem(`${dest}: shipped by ${a.plugin} and ${b.plugin} with different bytes (make them identical, or have the plugins name each other in conflictsWith)`);
    }
  }
}

// ── Modes and runtime downloads ──────────────────────────────────────────────────────────────
let indexModes = null;
try {
  const out = execFileSync('git', ['-C', root, 'ls-files', '-s', '--', 'plugins'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
  indexModes = new Map(out.split('\n').filter(Boolean).map((l) => [l.split('\t')[1], l.split(' ')[0]]));
} catch {
  indexModes = new Map();
}
for (const p of plugins) {
  const execs = [
    ...walk(join(p.dir, 'bin')),
    ...(existsSync(join(p.dir, 'scripts')) ? readdirSync(join(p.dir, 'scripts')).filter((f) => f.endsWith('.sh')).map((f) => join(p.dir, 'scripts', f)) : []),
  ];
  for (const f of execs) {
    const r = rel(f);
    const mode = indexModes.get(r);
    if (mode !== undefined) {
      if (mode !== '100755') problem(`${r}: mode ${mode} in the git index, expected 100755 (git update-index --chmod=+x)`);
    } else if ((statSync(f).mode & 0o111) === 0) {
      problem(`${r}: not executable (chmod +x before it is committed)`);
    }
  }
  for (const sub of ['scripts', 'bin', 'libexec', 'hooks']) {
    for (const f of walk(join(p.dir, sub))) {
      read(f).split('\n').forEach((line, i) => {
        const s = line.trim();
        if (s.startsWith('#') || s.startsWith('//')) return;
        if (DOWNLOAD.test(s) || DOWNLOAD_EXEC.test(s)) problem(`${rel(f)}:${i + 1}: runtime code must not download or install anything: ${s.slice(0, 100)}`);
      });
    }
  }
}

// ── Generated blocks ─────────────────────────────────────────────────────────────────────────
const LANG = {
  en: {
    head: '| Component | Kind | What it does | How to use | Why it helps | Docs |',
    kinds: { hook: 'Hook', command: 'Command', agent: 'Agent', skill: 'Skill', workflow: 'Workflow' },
    optional: 'optional',
    on: 'on',
    matchers: { edits: 'file edits', github: 'GitHub MCP writes', other: 'several tools' },
    userOnly: 'you start it',
    empty: 'No hooks, commands, agents, skills or workflows.',
    noPage: '(no page yet)',
  },
  id: {
    head: '| Komponen | Jenis | Fungsinya | Cara pakai | Manfaatnya | Dokumen |',
    kinds: { hook: 'Hook', command: 'Perintah', agent: 'Agen', skill: 'Skill', workflow: 'Workflow' },
    optional: 'opsional',
    on: 'pada',
    matchers: { edits: 'edit berkas', github: 'penulisan lewat GitHub MCP', other: 'beberapa tool' },
    userOnly: 'Anda yang memulai',
    empty: 'Tanpa hook, perintah, agen, skill, atau workflow.',
    noPage: '(belum ada halaman)',
  },
};

function catalogBlock(list, fromDir, lang = 'en') {
  const L = LANG[lang];
  const link = (page) => relative(fromDir, join(root, page)).split(sep).join('/');
  // A short matcher stays as code; a long one (a tool alternation that would stretch the column)
  // becomes a plain label. The exact matcher lives in the plugin's hooks/hooks.json.
  const matcherLabel = (m) => {
    if (m.length <= 24 && !/[()|]/.test(m)) return `\`${m}\``;
    if (/\b(Write|Edit|MultiEdit)\b/.test(m)) return L.matchers.edits;
    if (/github/i.test(m)) return L.matchers.github;
    return L.matchers.other;
  };
  const kindLabel = (c) => {
    if (c.kind === 'hook') {
      const on = c.on.replace(/ on /g, ` ${L.on} `).replace(/`([^`]+)`/g, (_, m) => matcherLabel(m));
      return `${L.kinds.hook} (${on})`;
    }
    if (c.kind === 'workflow') return c.optional ? `${L.kinds.workflow} (${L.optional})` : L.kinds.workflow;
    return c.userOnly ? `${L.kinds[c.kind]} (${L.userOnly})` : L.kinds[c.kind];
  };
  const out = [GENERATED_NOTE, ''];
  for (const p of list) {
    if (list.length > 1) out.push(`### ${p.name}`, '');
    if (p.comps.length === 0) {
      out.push(L.empty, '');
      continue;
    }
    out.push(L.head, '| --- | --- | --- | --- | --- | --- |');
    for (const c of p.comps) {
      const n = noteOf(c) ?? {};
      const docs = existsSync(join(root, c.page)) ? `[${c.name}](${link(c.page)})` : L.noPage;
      const what = lang === 'id' ? n.id?.what : c.desc;
      const use = lang === 'id' ? n.id?.use : n.use;
      const why = lang === 'id' ? n.id?.why : n.why;
      // "How to use" is written as Markdown (it holds `code`): only its pipes are escaped.
      const md = (v) => String(v ?? '').replace(/\s+/g, ' ').replace(/\|/g, '\\|').trim();
      out.push(`| \`${cell(c.invoke)}\` | ${cell(kindLabel(c))} | ${lang === 'id' ? md(what) : cell(what)} | ${md(use)} | ${md(why)} | ${docs} |`);
    }
    out.push('');
  }
  return out.join('\n');
}

// A plugin's role decides its install lines: agent-core, a stack plugin (it names the stacks it
// conflicts with), or an add-on that sits next to any stack.
function roleOf(p) {
  if (p.name === CORE) return 'core';
  return (conflicts.get(p.name)?.size ?? 0) > 0 ? 'stack' : 'addon';
}
function pluginInstall(p, template) {
  const role = roleOf(p);
  const install = role === 'core'
    ? ['/plugin install agent-core@agent-config-kit']
    : ['/plugin install agent-core@agent-config-kit', `/plugin install ${p.name}@agent-config-kit`];
  const note = {
    core: 'Most repos add one stack plugin as well; each one installs agent-core as its dependency, and its own setup plans agent-core\'s files in the same draft.',
    stack: `${p.name} depends on agent-core, so installing it installs agent-core too.`,
    addon: `${p.name} is an add-on: install and set up your stack plugin first (or use agent-core alone), then add it. It depends on agent-core, so installing it installs agent-core too.`,
  }[role];
  const text = template
    .replace(/\{\{install\}\}/g, install.join('\n   '))
    .replace(/\{\{setup\}\}/g, `/${p.name}:setup`)
    .replace(/\{\{note\}\}/g, note)
    .replace(/\{\{plugin\}\}/g, p.name);
  if (/\{\{[a-z]+\}\}/.test(text)) problem(`docs/install-block.plugin.md: unknown placeholder ${text.match(/\{\{[a-z]+\}\}/)[0]}`);
  return text;
}

// ── Every installed file ─────────────────────────────────────────────────────────────────────
const FILES_LANG = {
  en: {
    head: '| File | When setup installs it | What it is |',
    summary: (p, n) => `<strong>${p}</strong>: ${n} files`,
    always: 'always; sync keeps it current',
    kept: 'sync keeps it current',
    seed: 'once; then yours',
    starter: 'once, if missing; then yours',
    held: 'held until a release pins the reusable workflow to a real commit',
    when: (conds) => `with ${conds}`,
    merged: 'merged into yours (additive; your values win)',
    claudeBlock: 'one managed block, appended',
    claudeStarter: 'the starter, when the repo has no CLAUDE.md',
    gitignore: (n) => `one managed block (${n} lines)`,
    scripts: (names) => `missing scripts only: ${names}`,
    byHand: (f) => `by hand: the draft names ${f}`,
    lock: 'written last; its presence turns the hooks on',
    lockWhat: 'The record of what setup wrote; commit it',
  },
  id: {
    head: '| Berkas | Kapan setup memasangnya | Isinya (judul berkasnya) |',
    summary: (p, n) => `<strong>${p}</strong>: ${n} berkas`,
    always: 'selalu; sync menjaganya tetap terbaru',
    kept: 'sync menjaganya tetap terbaru',
    seed: 'sekali; lalu milik Anda',
    starter: 'sekali, jika belum ada; lalu milik Anda',
    held: 'ditahan sampai sebuah rilis mem-pin reusable workflow ke commit sungguhan',
    when: (conds) => `jika ${conds}`,
    merged: 'digabung ke milik Anda (hanya menambah; nilai Anda yang menang)',
    claudeBlock: 'satu blok terkelola, ditambahkan di akhir',
    claudeStarter: 'starter-nya, jika repo belum punya CLAUDE.md',
    gitignore: (n) => `satu blok terkelola (${n} baris)`,
    scripts: (names) => `hanya script yang belum ada: ${names}`,
    byHand: (f) => `manual: draft menyebut ${f}`,
    lock: 'ditulis terakhir; keberadaannya menyalakan hook',
    lockWhat: 'Catatan apa yang ditulis setup; commit berkas ini',
  },
};

// The first Markdown heading, or the first sentence of the first comment block.
function describe(file) {
  let text;
  try {
    text = read(file);
  } catch {
    return '';
  }
  const base = file.split(sep).pop();
  if (/\.(md|mdx)(\.starter)?$/.test(base) || /\.md\.starter$/.test(base)) {
    const body = text.startsWith('---\n') ? text.slice(text.indexOf('\n---', 4) + 4) : text;
    const m = body.match(/^#\s+(.+)$/m);
    return m ? m[1].trim() : '';
  }
  const lines = text.split('\n');
  const block = [];
  for (const raw of lines.slice(0, 40)) {
    const l = raw.trim();
    if (!block.length && (l === '' || l.startsWith('#!') || /^#\s*shellcheck\b/.test(l) || /^\/\/\s*@ts-/.test(l) || /^(import|export|const|let|from|use)\b/.test(l) || l === '/**')) {
      if (/^(import|export|const|let|use)\b/.test(l)) break;
      continue;
    }
    const m = l.match(/^(?:#|\/\/|\*|\/\*\*?)\s?(.*?)(?:\s*\*\/)?$/);
    if (!m) break;
    if (/^\s*shellcheck\b/.test(m[1])) continue;
    if (m[1] === '' && block.length) break;
    if (m[1] !== '') block.push(m[1]);
  }
  if (block.length) return firstSentence(block.join(' ')).replace(/:$/, '');
  if (/\.ya?ml$/.test(base)) {
    const m = text.match(/^name:\s*(.+)$/m);
    if (m) return m[1].trim().replace(/^['"]|['"]$/g, '');
  }
  return '';
}

function filesBlock(lang) {
  const L = FILES_LANG[lang];
  const out = [GENERATED_NOTE, ''];
  const described = notes?.files ?? {};
  for (const p of plugins) {
    const st = stacks.get(p.name);
    if (!st) continue;
    const { dir, setup } = st;
    const questions = setup.questions ?? [];
    const seeds = setup.seed ?? [];
    const rows = [];
    const matchAny = (globs, d) => globs.some((g) => globRe(g).test(d));
    const walkT = (d) => {
      for (const e of readdirSync(d, { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : 1))) {
        const full = join(d, e.name);
        const r = relative(dir, full).split(sep).join('/');
        if (r === '_kit' || r.startsWith('_kit/')) continue;
        if (e.isDirectory()) walkT(full);
        else rows.push({ full, r });
      }
    };
    walkT(dir);
    const table = [];
    for (const { full, r } of rows) {
      const starter = r.endsWith('.starter');
      const dest = starter ? r.slice(0, -'.starter'.length) : r;
      let when;
      if (dest === '.claude/settings.json') when = L.merged;
      else if (dest === 'CLAUDE.md') when = L.claudeStarter;
      else {
        const conds = [];
        for (const q of questions) {
          const gate = q.install ?? {};
          const gated = Object.values(gate).flat();
          if (gated.length && matchAny(gated, dest)) {
            const yes = Object.entries(gate).filter(([, globs]) => matchAny(globs, dest)).map(([c]) => `\`${q.id}=${c}\``);
            conds.push(yes.join(' / '));
          }
        }
        let base = starter ? L.starter : matchAny(seeds, dest) ? L.seed : null;
        if (/@0{40}(?![0-9a-fA-F])/.test(read(full))) base = L.held;
        when = conds.length ? `${L.when(conds.join(', '))}; ${base ?? L.kept}` : base ?? L.always;
      }
      const name = dest.split('/').pop();
      const what = describe(full) || described[dest]?.[lang] || described[name]?.[lang] || described[dest]?.en || described[name]?.en || '';
      if (!what && lang === 'en') problem(`${rel(full)}: no "What it is" for the installed-files table (a heading, a first comment, or an entry in docs/catalog.json "files")`);
      table.push(`| \`${cell(dest)}\` | ${when} | ${cell(what)} |`);
    }
    const kitMd = join(dir, '_kit', 'claude-md.md');
    if (existsSync(kitMd) && read(kitMd).trim()) table.push(`| \`CLAUDE.md\` | ${L.claudeBlock} | \`## Agent config kit\` |`);
    if ((setup.gitignore ?? []).length) table.push(`| \`.gitignore\` | ${L.gitignore(setup.gitignore.length)} | ${setup.gitignore.map((l) => `\`${cell(l)}\``).join(', ')} |`);
    const scripts = Object.keys(setup.packageScripts ?? {});
    if (scripts.length) table.push(`| \`package.json\` | ${L.scripts(cell(scripts.join(', ')))} | \`scripts\` |`);
    for (const [target, snippet] of Object.entries(setup.snippets ?? {})) table.push(`| \`${cell(target)}\` | ${L.byHand(`\`_kit/${cell(snippet)}\``)} | |`);
    if (p.name === CORE) table.push(`| \`.claude/agent-config-kit.lock\` | ${L.lock} | ${L.lockWhat} |`);
    out.push('<details>', `<summary>${L.summary(p.name, table.length)}</summary>`, '', L.head, '| --- | --- | --- |', ...table, '', '</details>', '');
  }
  return out.join('\n');
}

const readOptional = (p) => (existsSync(p) ? read(p).trimEnd() + '\n' : null);
const installText = readOptional(join(root, 'docs', 'install-block.md'));
const installTextId = readOptional(join(root, 'docs', 'install-block.id.md'));
const installTemplate = readOptional(join(root, 'docs', 'install-block.plugin.md'));

function replaceBlock(text, [start, end], body, file) {
  const a = text.indexOf(start);
  const b = text.indexOf(end);
  if (a < 0 && b < 0) return { text, found: false };
  if (a < 0 || b < 0 || b < a || text.indexOf(start, a + 1) >= 0 || text.indexOf(end, b + 1) >= 0) {
    problem(`${file}: ${start} / ${end} must appear once each, in that order`);
    return { text, found: true };
  }
  return { text: `${text.slice(0, a + start.length)}\n${body.trimEnd()}\n${text.slice(b)}`, found: true };
}

const targets = [];
targets.push({ file: join(root, 'README.md'), plugins, required: true, lang: 'en', install: installText, installFile: 'docs/install-block.md' });
targets.push({ file: join(root, 'README.id.md'), plugins, required: false, lang: 'id', install: installTextId, installFile: 'docs/install-block.id.md' });
for (const p of plugins) {
  targets.push({ file: join(p.dir, 'README.md'), plugins: [p], required: true, plugin: p.name, lang: 'en',
    install: installTemplate === null ? null : pluginInstall(p, installTemplate), installFile: 'docs/install-block.plugin.md' });
}

for (const t of targets) {
  const r = rel(t.file);
  if (!existsSync(t.file)) {
    if (t.required) problem(`${r}: missing`);
    continue;
  }
  const before = read(t.file);
  checkHidden(t.file, before);
  let text = before;
  const cat = replaceBlock(text, MARK.catalog, catalogBlock(t.plugins, dirname(t.file), t.lang), r);
  text = cat.text;
  if (!cat.found && !t.plugin) problem(`${r}: no ${MARK.catalog[0]} / ${MARK.catalog[1]} block for the plugin catalog`);
  let ins = { found: false };
  if (t.install !== null) {
    ins = replaceBlock(text, MARK.install, t.install, r);
    text = ins.text;
  } else if (before.includes(MARK.install[0])) {
    problem(`${r}: has install markers but ${t.installFile} is missing`);
  }
  if (!ins.found && (r === 'README.md' || t.plugin)) problem(`${r}: no ${MARK.install[0]} / ${MARK.install[1]} block for the install steps`);
  if (!t.plugin && stacks.size) {
    const fl = replaceBlock(text, MARK.files, filesBlock(t.lang), r);
    text = fl.text;
  }
  if (text !== before) {
    if (check) problem(`${r}: generated block is stale; run: node scripts/catalog.mjs`);
    else {
      writeFileSync(t.file, text);
      console.log(`catalog: updated ${r}`);
    }
  }
}

// ── Report ───────────────────────────────────────────────────────────────────────────────────
const count = plugins.reduce((n, p) => n + p.comps.length, 0);
if (problems.length) {
  for (const m of problems) console.log(`FAIL: ${m}`);
  console.log(`catalog: ${plugins.length} plugin(s), ${count} component(s), ${problems.length} problem(s)`);
  process.exit(1);
}
console.log(`catalog: ${plugins.length} plugin(s), ${count} component(s), all invariants hold${check ? '' : ', blocks current'}`);
