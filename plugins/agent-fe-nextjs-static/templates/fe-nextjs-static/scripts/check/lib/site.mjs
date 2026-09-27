// Shared helpers for the static-site checks in scripts/check/ (installed by agent-fe-nextjs-static).
// Node >= 20, no dependencies, no network. Each check reads the project from the current folder
// (or --root) and the built pages from --dir (default: the mode's output folder).
//
// Exit codes, the same for every check: 0 clean (warnings allowed), 1 at least one error,
// 2 usage or setup problem (bad flag, unreadable config, nothing built yet).
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, sep } from 'node:path';

const CONFIG_FILE = 'scripts/check/site.config.json';

const DEFAULTS = {
  mode: 'auto',
  siteUrl: '',
  siteUrlEnv: 'NEXT_PUBLIC_SITE_URL',
  basePath: '',
  outDir: '',
  endpoints: ['app/api/**', 'src/app/api/**'],
  sitemapExclude: [],
  headersFile: 'public/_headers',
  description: { minChars: 50, maxChars: 160 },
  ogImage: { minWidth: 1200, minHeight: 630, maxKB: 5000 },
  images: { maxKB: 250, maxWidthPx: 2560, modernFormatKB: 100, unusedIgnore: [] },
  fonts: { maxFamilies: 2, maxFiles: 6, maxTotalKB: 300 },
  bundle: { maxJsKB: 250, maxCssKB: 50 },
  a11y: { standard: 'WCAG2AA', exclude: [] },
};

// Pages that are never indexable and never in a sitemap: error and not-found pages.
const SPECIAL_PAGES = new Set([
  '404.html',
  '500.html',
  '_not-found.html',
  '_global-error.html',
  '_error.html',
]);
const SOURCE_ROOTS = ['app', 'src', 'components', 'lib', 'content', 'messages', 'pages', 'styles'];
const SOURCE_EXT = /\.(tsx?|jsx?|mjs|cjs|mts|cts|css|scss|mdx?|json)$/;

/** Parses `--flag value` / `--flag=value` / `--switch` arguments; the rest are positional. */
function parseArgs(argv, switches = []) {
  const args = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) {
      args._.push(a);
      continue;
    }
    const eq = a.indexOf('=');
    const name = a.slice(2, eq === -1 ? undefined : eq);
    if (eq !== -1) args[name] = a.slice(eq + 1);
    else if (switches.includes(name)) args[name] = true;
    else if (i + 1 < argv.length) args[name] = argv[++i];
    else throw new UsageError(`--${name} needs a value`);
  }
  return args;
}

export class UsageError extends Error {}

function merge(base, extra) {
  const out = { ...base };
  for (const [k, v] of Object.entries(extra || {})) {
    if (k.startsWith('//')) continue;
    out[k] =
      v && typeof v === 'object' && !Array.isArray(v) && base[k] && typeof base[k] === 'object'
        ? merge(base[k], v)
        : v;
  }
  return out;
}

/**
 * The config file merged over the defaults. A missing file means every default.
 * @public for your own scripts (and the kit's tests), which build on openSite() like the checks do.
 */
export function loadConfig(root, file = CONFIG_FILE) {
  const path = join(root, file);
  if (!existsSync(path)) return merge(DEFAULTS, {});
  let data;
  try {
    data = JSON.parse(readFileSync(path, 'utf8'));
  } catch (e) {
    throw new UsageError(`${file} is not valid JSON: ${e.message}`);
  }
  if (!data || typeof data !== 'object' || Array.isArray(data))
    throw new UsageError(`${file} must hold a JSON object`);
  const cfg = merge(DEFAULTS, data);
  if (!['auto', 'export', 'ssg-with-endpoints'].includes(cfg.mode)) {
    throw new UsageError(
      `${file}: mode must be auto, export or ssg-with-endpoints (got ${JSON.stringify(cfg.mode)})`,
    );
  }
  return cfg;
}

const NEXT_CONFIGS = [
  'next.config.ts',
  'next.config.mjs',
  'next.config.js',
  'next.config.cjs',
  'next.config.mts',
];

/** The first next.config.* in the project, as { file, text }, or null. */
export function readNextConfig(root) {
  for (const f of NEXT_CONFIGS) {
    const p = join(root, f);
    if (existsSync(p)) return { file: f, text: stripComments(readFileSync(p, 'utf8')) };
  }
  return null;
}

/** export when next.config.* sets output: 'export', else ssg-with-endpoints; config overrides. */
export function detectMode(root, cfg) {
  if (cfg.mode !== 'auto') return cfg.mode;
  const nc = readNextConfig(root);
  return nc && /\boutput\s*:\s*['"`]export['"`]/.test(nc.text) ? 'export' : 'ssg-with-endpoints';
}

/** The production origin (no trailing slash) from the config or its env variable, or ''. */
export function siteUrl(cfg) {
  const raw = (cfg.siteUrl || (cfg.siteUrlEnv && process.env[cfg.siteUrlEnv]) || '').trim();
  if (!raw) return '';
  let u;
  try {
    u = new URL(raw);
  } catch {
    throw new UsageError(`siteUrl ${JSON.stringify(raw)} is not an absolute URL`);
  }
  if (u.protocol !== 'https:' && u.protocol !== 'http:')
    throw new UsageError(`siteUrl must be http(s): ${raw}`);
  return (u.origin + u.pathname).replace(/\/+$/, '');
}

function walk(dir, skip = () => false) {
  const out = [];
  const stack = [dir];
  while (stack.length) {
    const d = stack.pop();
    let entries;
    try {
      entries = readdirSync(d, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const e of entries) {
      const p = join(d, e.name);
      if (skip(p, e)) continue;
      if (e.isDirectory()) stack.push(p);
      else if (e.isFile()) out.push(p);
    }
  }
  return out.toSorted();
}

export const toPosix = (p) => p.split(sep).join('/');

/**
 * The built site: where its pages are and how a URL path maps to a file.
 * export: every file is under outDir (default out/).
 * ssg-with-endpoints: prerendered pages under .next/server/app (metadata routes as <name>.body),
 * /_next/static/* under .next/static, and everything else from public/.
 */
export function openSite(root, cfg, dirFlag) {
  const mode = detectMode(root, cfg);
  const pagesDir = join(
    root,
    dirFlag || cfg.outDir || (mode === 'export' ? 'out' : '.next/server/app'),
  );
  if (!existsSync(pagesDir) || !statSync(pagesDir).isDirectory()) {
    throw new UsageError(
      `${toPosix(relative(root, pagesDir)) || '.'} does not exist: build the site first (next build)`,
    );
  }
  const base = (cfg.basePath || '').replace(/\/+$/, '');
  const ssg = mode !== 'export' && !dirFlag && !cfg.outDir;
  const files = walk(
    pagesDir,
    (p, e) => e.isDirectory() && (e.name === '_next' || e.name.endsWith('.segments')),
  );
  const pages = [];
  for (const f of files) {
    const rel = toPosix(relative(pagesDir, f));
    if (!rel.endsWith('.html')) continue;
    const special = SPECIAL_PAGES.has(rel);
    let path;
    if (rel === 'index.html') path = '/';
    else if (rel.endsWith('/index.html')) path = `/${rel.slice(0, -'index.html'.length)}`;
    else path = `/${rel.slice(0, -'.html'.length)}`;
    pages.push({ file: f, rel: toPosix(relative(root, f)), path: base + path, special });
  }

  const candidates = (p) => {
    const clean = p.replace(/^\/+/, '');
    const list = [];
    if (ssg) {
      if (clean.startsWith('_next/static/'))
        return [join(root, '.next/static', clean.slice('_next/static/'.length))];
      if (clean === '' || clean.endsWith('/')) list.push(join(pagesDir, clean, 'index.html'));
      else
        list.push(
          join(pagesDir, `${clean}.html`),
          join(pagesDir, clean, 'index.html'),
          join(pagesDir, `${clean}.body`),
        );
      if (clean !== '') list.push(join(root, 'public', clean));
      return list;
    }
    if (clean === '' || clean.endsWith('/')) return [join(pagesDir, clean, 'index.html')];
    return [
      join(pagesDir, clean),
      join(pagesDir, `${clean}.html`),
      join(pagesDir, clean, 'index.html'),
    ];
  };

  /** The file serving a same-site URL path (query and hash ignored), or null. */
  const resolvePath = (requested) => {
    let p = requested.split('#')[0].split('?')[0];
    try {
      p = decodeURIComponent(p);
    } catch {
      return null;
    }
    if (base) {
      if (p !== base && !p.startsWith(`${base}/`)) return null;
      p = p.slice(base.length) || '/';
    }
    if (p.split('/').includes('..')) return null;
    for (const c of candidates(p)) {
      if (existsSync(c) && statSync(c).isFile()) return c;
    }
    return null;
  };

  return { mode, root, pagesDir, pages, resolvePath, basePath: base };
}

/** Normalises an absolute URL for comparison: origin + path without a trailing slash. */
export function normUrl(u) {
  try {
    const x = new URL(u);
    const path = x.pathname.replace(/\/+$/, '') || '/';
    return `${x.origin}${path}`;
  } catch {
    return u;
  }
}

/** True when `u` is an absolute URL on the site (siteUrl() form: origin, optional path, no slash). */
export function onSite(u, site) {
  if (!site || !/^https?:\/\//i.test(u)) return false;
  const n = normUrl(u);
  return n === site || n === `${site}/` || n.startsWith(`${site}/`);
}

/** The path of an absolute URL, or of a root-relative one; null for anything else. */
export function urlPath(u) {
  if (u.startsWith('/') && !u.startsWith('//')) return u;
  try {
    return new URL(u).pathname;
  } catch {
    return null;
  }
}

const ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: '\u00a0' };

function decodeEntities(s) {
  return s.replace(/&(#x[0-9a-f]+|#[0-9]+|[a-z]+);/gi, (m, e) => {
    if (e[0] === '#') {
      const code =
        e[1] === 'x' || e[1] === 'X' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
      return Number.isFinite(code) ? String.fromCodePoint(code) : m;
    }
    return ENTITIES[e.toLowerCase()] ?? m;
  });
}

const ATTR = /([^\s"'<>/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g;

function parseAttrs(src) {
  const attrs = {};
  for (const m of src.matchAll(ATTR)) {
    const name = m[1].toLowerCase();
    if (name in attrs) continue;
    attrs[name] = decodeEntities(m[2] ?? m[3] ?? m[4] ?? '');
  }
  return attrs;
}

const TOKEN =
  /<!--[\s\S]*?-->|<(script|style|title|textarea)\b((?:[^>"']|"[^"]*"|'[^']*')*)>([\s\S]*?)<\/\1\s*>|<([a-zA-Z][a-zA-Z0-9:-]*)\b((?:[^>"']|"[^"]*"|'[^']*')*)>/gi;

/**
 * A small HTML reader, enough for built pages: start tags with their attributes, and the raw
 * text of script, style, title and textarea elements. Comments are skipped.
 */
export function parseHtml(html) {
  const tags = [];
  for (const m of html.matchAll(TOKEN)) {
    if (m[0].startsWith('<!--')) continue;
    if (m[1]) tags.push({ name: m[1].toLowerCase(), attrs: parseAttrs(m[2]), text: m[3] });
    else tags.push({ name: m[4].toLowerCase(), attrs: parseAttrs(m[5]) });
  }
  const all = (name) => tags.filter((t) => t.name === name);
  const meta = (key, value) =>
    all('meta').filter((t) => (t.attrs[key] || '').toLowerCase() === value);
  const links = (rel) =>
    all('link').filter((t) => (t.attrs.rel || '').toLowerCase().split(/\s+/).includes(rel));
  return { tags, all, meta, links };
}

/** True when a page asks not to be indexed (robots or googlebot meta). */
export function isNoindex(doc) {
  return [...doc.meta('name', 'robots'), ...doc.meta('name', 'googlebot')].some((t) =>
    /\b(noindex|none)\b/i.test(t.attrs.content || ''),
  );
}

/** Removes // and /* *\/ comments from JS/TS/CSS source, keeping strings (and line numbers). */
export function stripComments(src) {
  let out = '';
  let i = 0;
  const n = src.length;
  while (i < n) {
    const c = src[i];
    const d = src[i + 1];
    if (c === '/' && d === '/') {
      while (i < n && src[i] !== '\n') i++;
      continue;
    }
    if (c === '/' && d === '*') {
      i += 2;
      while (i < n && !(src[i] === '*' && src[i + 1] === '/')) {
        if (src[i] === '\n') out += '\n';
        i++;
      }
      i += 2;
      continue;
    }
    if (c === '"' || c === "'" || c === '`') {
      const q = c;
      out += c;
      i++;
      while (i < n && src[i] !== q) {
        if (src[i] === '\\') {
          out += src[i] + (src[i + 1] ?? '');
          i += 2;
          continue;
        }
        if (q !== '`' && src[i] === '\n') break;
        out += src[i];
        i++;
      }
      if (i < n && src[i] === q) {
        out += q;
        i++;
      }
      continue;
    }
    out += c;
    i++;
  }
  return out;
}

/** Source files a site is built from (not node_modules, build output or dot folders). */
export function sourceFiles(root) {
  const files = [];
  for (const r of SOURCE_ROOTS) {
    const d = join(root, r);
    if (!existsSync(d)) continue;
    files.push(
      ...walk(
        d,
        (p, e) => e.isDirectory() && (e.name === 'node_modules' || e.name.startsWith('.')),
      ).filter((f) => SOURCE_EXT.test(f)),
    );
  }
  for (const f of NEXT_CONFIGS) if (existsSync(join(root, f))) files.push(join(root, f));
  return files;
}

/** Every file under a folder, as absolute paths; [] when it does not exist. */
export function filesUnder(dir, skipDirs = []) {
  if (!existsSync(dir)) return [];
  return walk(dir, (p, e) => e.isDirectory() && skipDirs.includes(e.name));
}

/** A glob as a RegExp over posix paths: ** crosses folders, * and ? do not. */
function globRe(pattern) {
  let re = '';
  for (let i = 0; i < pattern.length; i++) {
    const c = pattern[i];
    if (c === '*' && pattern[i + 1] === '*') {
      if (pattern[i + 2] === '/') {
        re += '(?:.*/)?';
        i += 2;
      } else {
        re += '.*';
        i += 1;
      }
    } else if (c === '*') re += '[^/]*';
    else if (c === '?') re += '[^/]';
    else re += c.replace(/[.+^${}()|[\]\\]/g, '\\$&');
  }
  return new RegExp(`^${re}$`);
}

export const matchesAny = (path, globs) => globs.some((g) => globRe(g).test(path));

/** Width and height of a PNG, JPEG, GIF or WebP from its header bytes, or null. */
export function imageSize(buf) {
  if (buf.length >= 24 && buf.readUInt32BE(0) === 0x89504e47) {
    return { type: 'png', width: buf.readUInt32BE(16), height: buf.readUInt32BE(20) };
  }
  if (buf.length >= 10 && buf.toString('ascii', 0, 3) === 'GIF') {
    return { type: 'gif', width: buf.readUInt16LE(6), height: buf.readUInt16LE(8) };
  }
  if (
    buf.length >= 30 &&
    buf.toString('ascii', 0, 4) === 'RIFF' &&
    buf.toString('ascii', 8, 12) === 'WEBP'
  ) {
    const kind = buf.toString('ascii', 12, 16);
    if (kind === 'VP8X')
      return { type: 'webp', width: 1 + buf.readUIntLE(24, 3), height: 1 + buf.readUIntLE(27, 3) };
    if (kind === 'VP8L') {
      const b = buf.readUInt32LE(21);
      return { type: 'webp', width: 1 + (b & 0x3fff), height: 1 + ((b >> 14) & 0x3fff) };
    }
    if (kind === 'VP8 ')
      return {
        type: 'webp',
        width: buf.readUInt16LE(26) & 0x3fff,
        height: buf.readUInt16LE(28) & 0x3fff,
      };
  }
  if (buf.length >= 4 && buf[0] === 0xff && buf[1] === 0xd8) {
    let i = 2;
    while (i + 9 < buf.length) {
      if (buf[i] !== 0xff) {
        i++;
        continue;
      }
      const marker = buf[i + 1];
      if (marker >= 0xc0 && marker <= 0xcf && ![0xc4, 0xc8, 0xcc].includes(marker)) {
        return { type: 'jpeg', height: buf.readUInt16BE(i + 5), width: buf.readUInt16BE(i + 7) };
      }
      i += 2 + buf.readUInt16BE(i + 2);
    }
    return { type: 'jpeg', width: 0, height: 0 };
  }
  if (
    buf.length >= 12 &&
    buf.toString('ascii', 4, 8) === 'ftyp' &&
    /avif|avis/.test(buf.toString('ascii', 8, 12))
  ) {
    return { type: 'avif', width: 0, height: 0 };
  }
  return null;
}

/** Collects findings and prints them the same way for every check. */
class Report {
  constructor(name) {
    this.name = name;
    this.errors = 0;
    this.warnings = 0;
    this.notes = [];
  }
  error(where, msg) {
    this.errors++;
    console.log(`${this.name}: ERROR ${where}: ${msg}`);
  }
  warn(where, msg) {
    this.warnings++;
    console.log(`${this.name}: WARN  ${where}: ${msg}`);
  }
  info(msg) {
    console.log(`${this.name}: ${msg}`);
  }
  finish(summary) {
    const verdict = this.errors ? 'FAIL' : 'ok';
    console.log(
      `${this.name}: ${verdict} - ${this.errors} error(s), ${this.warnings} warning(s)${summary ? `; ${summary}` : ''}`,
    );
    return this.errors ? 1 : 0;
  }
}

/** Runs a check's main(args) with the shared flags and exit codes. */
export async function run(name, main, { switches = [] } = {}) {
  try {
    const args = parseArgs(process.argv.slice(2), switches);
    const root = args.root || process.cwd();
    const cfg = loadConfig(root, args.config || CONFIG_FILE);
    const code = await main({ args, root, cfg, report: new Report(name) });
    process.exitCode = code;
  } catch (e) {
    if (e instanceof UsageError) {
      console.error(`${name}: ${e.message}`);
      process.exitCode = 2;
      return;
    }
    throw e;
  }
}
