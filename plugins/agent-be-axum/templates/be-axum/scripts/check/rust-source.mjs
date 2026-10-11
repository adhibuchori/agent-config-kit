#!/usr/bin/env node
/**
 * Rust source checks that the compiler and clippy do not make, over every tracked or new *.rs
 * file (target/ and .sqlx/ aside, and a file that says @generated in its first five lines):
 *
 *   LINES     at most 200 lines of code per file; blank and comment-only lines do not count, and
 *             every line of a multi-line string does (Rule 22).
 *   HANDLERS  at most 15 lines of code in the body of a #[utoipa::path] handler (Rule 5).
 *   ROUTES    a path literal ("/...") only in src/routes/paths.rs; .route(, .route_service(,
 *             .nest_service( and Router::new() only in src/routes/mod.rs and src/lib.rs (Rule 10).
 *   LAYERS    no sqlx in src/routes/; no axum, tower, tower_http or http in a domain folder; no
 *             crate::routes or crate::<domain> in src/platform/; .begin( only in a repo.rs
 *             (Rules 2 and 16); crate::payload only in src/routes/, src/lib.rs and src/payload/
 *             itself, so the payload contract stays at the edge (Rule 31).
 *   SQL       no SELECT *; a query read with fetch_all or fetch has a LIMIT (or = ANY(...));
 *             AssertSqlSafe( only under a `// sql-safe: <reason>` comment (Rule 14).
 *   ALLOW     no #![allow( anywhere, since clippy's allow_attributes reads outer attributes only;
 *             and ErrorCode never derives or implements Deserialize, which would hide a code
 *             nothing builds from dead_code (Rules 6 and 23).
 *
 * A domain folder is any src/<name>/ other than platform, routes and bin. Test code (tests/,
 * benches/, examples/, *_tests.rs) is held to LINES and ALLOW only.
 *
 *   node scripts/check/rust-source.mjs [file.rs ...]
 *   node scripts/check/rust-source.mjs --count file.rs ...   print each file's lines of code
 *
 * Each finding is one line, `path:line: [CHECK] message`. The counting is a small Rust lexer:
 * line and nested block comments, strings with escapes, raw strings with any number of #, byte
 * and C string prefixes, and char literals told apart from lifetimes. Plain Node ESM, no
 * dependencies. Exit 0 clean, 1 on a finding, 2 when the files cannot be listed.
 */
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..');
const MAX_LINES = 200;
const MAX_HANDLER_LINES = 15;
const NOT_DOMAINS = new Set(['platform', 'routes', 'bin']);
const SKIPPED = /(^|\/)(target|\.sqlx|\.git|node_modules)\//;

const findings = [];
const report = (path, line, check, message) => findings.push(`${path}:${line}: [${check}] ${message}`);

/**
 * Lexes Rust source. Returns `events` (one {pos, line} per character of code and per line a
 * string literal spans), `strings` ({value, pos, end, line}), `comments` ({line, text}) and
 * `blanked`: the source with comments and literal contents turned to spaces, newlines kept.
 */
function lex(src) {
  const events = [];
  const strings = [];
  const comments = [];
  const out = src.split('');
  const n = src.length;
  let i = 0;
  let line = 1;
  const blank = (from, to) => {
    for (let k = from; k < to; k++) if (out[k] !== '\n') out[k] = ' ';
  };
  /* A literal from `start` to `end` (exclusive): every line it spans holds code. */
  const literal = (start, bodyStart, bodyEnd, end) => {
    events.push({ pos: start, line });
    strings.push({ value: src.slice(bodyStart, bodyEnd), pos: start, end, line });
    for (let k = start; k < end; k++) {
      if (src[k] === '\n') {
        line++;
        events.push({ pos: k + 1, line });
      }
    }
    blank(bodyStart, bodyEnd);
    i = end;
  };
  const identBefore = (k) => /[A-Za-z0-9_]/.test(src[k - 1] ?? '');
  while (i < n) {
    const c = src[i];
    if (c === '\n') {
      line++;
      i++;
    } else if (c === ' ' || c === '\t' || c === '\r') {
      i++;
    } else if (src.startsWith('//', i)) {
      const j = src.indexOf('\n', i) < 0 ? n : src.indexOf('\n', i);
      comments.push({ line, text: src.slice(i, j) });
      blank(i, j);
      i = j;
    } else if (src.startsWith('/*', i)) {
      const start = i;
      let depth = 1;
      i += 2;
      while (i < n && depth > 0) {
        if (src.startsWith('/*', i)) {
          depth++;
          i += 2;
        } else if (src.startsWith('*/', i)) {
          depth--;
          i += 2;
        } else {
          if (src[i] === '\n') line++;
          i++;
        }
      }
      blank(start, i);
    } else {
      const raw = identBefore(i) ? null : /^(?:b|c)?r(#*)"/.exec(src.slice(i, i + 260));
      const plain = raw || identBefore(i) ? null : /^(?:b|c)?"/.exec(src.slice(i, i + 2));
      if (raw) {
        const close = `"${raw[1]}`;
        const at = src.indexOf(close, i + raw[0].length);
        const bodyEnd = at < 0 ? n : at;
        literal(i, i + raw[0].length, bodyEnd, Math.min(n, bodyEnd + close.length));
      } else if (plain) {
        let j = i + plain[0].length;
        while (j < n && src[j] !== '"') j += src[j] === '\\' ? 2 : 1;
        literal(i, i + plain[0].length, Math.min(j, n), Math.min(j + 1, n));
      } else if (c === "'") {
        const ch = /^'(?:\\(?:u\{[0-9a-fA-F]{1,6}\}|x[0-9a-fA-F]{2}|.)|[^\\'\n])'/u.exec(src.slice(i, i + 16));
        events.push({ pos: i, line });
        if (ch) blank(i + 1, i + ch[0].length - 1);
        i += ch ? ch[0].length : 1;
      } else {
        events.push({ pos: i, line });
        i++;
      }
    }
  }
  return { events, strings, comments, blanked: out.join('') };
}

/** The distinct lines that hold code between two positions, both exclusive. */
function codeLinesBetween(events, from, to) {
  return new Set(events.filter((e) => e.pos > from && e.pos < to).map((e) => e.line));
}

/** The 1-based line of a position. */
function lineAt(text, pos) {
  let line = 1;
  for (let k = 0; k < pos; k++) if (text[k] === '\n') line++;
  return line;
}

/** The position of the brace that closes the one at `open`, in text without comments or strings. */
function closing(text, open) {
  let depth = 0;
  for (let k = open; k < text.length; k++) {
    if (text[k] === '{') depth++;
    else if (text[k] === '}' && --depth === 0) return k;
  }
  return text.length;
}

function checkLines(path, lexed) {
  const lines = [...new Set(lexed.events.map((e) => e.line))].sort((a, b) => a - b);
  if (lines.length > MAX_LINES) {
    report(path, lines[MAX_LINES], 'LINES', `${lines.length} lines of code, over ${MAX_LINES} (blank and comment lines do not count); split the file by what it does`);
  }
}

function checkHandlers(path, { events, blanked }) {
  for (const m of blanked.matchAll(/#\s*\[\s*utoipa::path\b/g)) {
    const fn = /\bfn\s+([A-Za-z_][A-Za-z0-9_]*)/g;
    fn.lastIndex = m.index;
    const head = fn.exec(blanked);
    if (!head) continue;
    const open = blanked.indexOf('{', head.index);
    if (open < 0) continue;
    const count = codeLinesBetween(events, open, closing(blanked, open)).size;
    if (count > MAX_HANDLER_LINES) {
      report(path, lineAt(blanked, head.index), 'HANDLERS', `handler ${head[1]} has ${count} lines of code in its body, over ${MAX_HANDLER_LINES}; move the work into the domain's service`);
    }
  }
}

function checkRoutes(path, { strings, blanked }) {
  if (path !== 'src/routes/paths.rs') {
    for (const s of strings) {
      if (/^\/([\w{}:*.~-]\S*)?$/.test(s.value)) report(path, s.line, 'ROUTES', `path literal "${s.value}" outside src/routes/paths.rs; name it there`);
    }
  }
  if (path === 'src/routes/mod.rs' || path === 'src/lib.rs') return;
  for (const m of blanked.matchAll(/\.(route|route_service|nest_service)\s*\(|(?<![A-Za-z0-9_])Router::new\s*\(/g)) {
    report(path, lineAt(blanked, m.index), 'ROUTES', `${m[0].replace(/\s*\($/, '(')} outside src/routes/mod.rs and src/lib.rs: a route enters through routes!, so the spec lists it`);
  }
}

function checkLayers(path, { blanked }, domains) {
  const at = (m) => lineAt(blanked, m.index);
  const [, top] = path.split('/');
  if (top === 'routes') {
    for (const m of blanked.matchAll(/(?<![A-Za-z0-9_:])sqlx\b/g)) report(path, at(m), 'LAYERS', 'sqlx in src/routes/: a handler calls its service, and the repo queries');
  } else if (top === 'platform' && domains.length) {
    const named = new RegExp(`\\bcrate::(routes|${domains.join('|')})\\b`, 'g');
    for (const m of blanked.matchAll(named)) report(path, at(m), 'LAYERS', `${m[0]} in src/platform/: the platform never names a route or a domain`);
  } else if (top === 'platform') {
    for (const m of blanked.matchAll(/\bcrate::routes\b/g)) report(path, at(m), 'LAYERS', `${m[0]} in src/platform/: the platform never names a route or a domain`);
  } else if (domains.includes(top)) {
    for (const m of blanked.matchAll(/(?<![A-Za-z0-9_:])(axum|tower|tower_http|http)::|\buse\s+(axum|tower|tower_http|http)\b/g)) {
      report(path, at(m), 'LAYERS', `${m[1] ?? m[2]} in a domain: HTTP stays in src/routes/ and src/platform/`);
    }
  }
  if (!path.endsWith('/repo.rs')) {
    for (const m of blanked.matchAll(/\.begin\s*\(/g)) report(path, at(m), 'LAYERS', 'a transaction opens only in a repo.rs, and stays short');
  }
  /* src/platform/ is held above when src/payload/ exists, as a domain the platform never names. */
  if (path !== 'src/lib.rs' && !['routes', 'payload', 'platform'].includes(top)) {
    for (const m of blanked.matchAll(/\bcrate::payload\b/g)) report(path, at(m), 'LAYERS', 'crate::payload outside src/routes/ and src/lib.rs: the payload layer opens and seals bodies at the edge, so handlers and domains see plaintext');
  }
}

function checkSql(path, { strings, comments, blanked }) {
  for (const s of strings) {
    const sql = s.value.replace(/\s+/g, ' ');
    if (/\bselect\s+(distinct\s+)?\*/i.test(sql)) report(path, s.line, 'SQL', 'SELECT *: name the columns, so a new column never changes what a cached statement returns');
    if (!/^\s*(with|select)\b/i.test(sql) || /\blimit\b|=\s*any\s*\(/i.test(sql)) continue;
    const end = blanked.indexOf(';', s.end);
    const rest = blanked.slice(s.end, end < 0 ? undefined : end);
    if (/\.fetch(_all)?\s*\(/.test(rest)) report(path, s.line, 'SQL', 'a list query without LIMIT: page it with LIMIT and a keyset WHERE');
  }
  for (const m of blanked.matchAll(/\bAssertSqlSafe\s*\(/g)) {
    const line = lineAt(blanked, m.index);
    const reasoned = comments.some((c) => c.line <= line && c.line >= line - 3 && /sql-safe:\s*\S/.test(c.text));
    if (!reasoned) report(path, line, 'SQL', 'AssertSqlSafe( needs a `// sql-safe: <reason>` comment on its line or just above');
  }
}

function checkAllow(path, { blanked }) {
  for (const m of blanked.matchAll(/#\s*!\s*\[\s*allow\s*\(/g)) {
    report(path, lineAt(blanked, m.index), 'ALLOW', '#![allow( switches lints off for a whole module and is never reported stale; use #[expect(lint, reason = "...")] on the item');
  }
  for (const m of blanked.matchAll(/\benum\s+ErrorCode\b/g)) {
    const before = blanked.slice(0, m.index);
    const attrs = before.slice(Math.max(before.lastIndexOf(';'), before.lastIndexOf('}')) + 1);
    if (/\bDeserialize\b/.test(attrs)) report(path, lineAt(blanked, m.index), 'ALLOW', 'ErrorCode derives Deserialize, which hides a code nothing builds from dead_code');
  }
  for (const m of blanked.matchAll(/\bimpl\b[^{;]*\bDeserialize\b[^{;]*\bfor\s+ErrorCode\b/g)) {
    report(path, lineAt(blanked, m.index), 'ALLOW', 'ErrorCode implements Deserialize, which hides a code nothing builds from dead_code');
  }
}

/** Every *.rs file git knows or would add, else every one on disk. */
function listFiles() {
  try {
    const out = execFileSync('git', ['ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', '*.rs'], {
      cwd: ROOT,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    });
    return [...new Set(out.split('\0').filter(Boolean))];
  } catch {
    const found = [];
    const walk = (dir) => {
      for (const name of readdirSync(join(ROOT, dir))) {
        const rel = dir ? `${dir}/${name}` : name;
        if (SKIPPED.test(`${rel}/`)) continue;
        if (statSync(join(ROOT, rel)).isDirectory()) walk(rel);
        else if (rel.endsWith('.rs')) found.push(rel);
      }
    };
    walk('');
    return found;
  }
}

const cwd = process.cwd();
const COUNT = process.argv[2] === '--count';
const args = process.argv.slice(COUNT ? 3 : 2);
if (COUNT) {
  for (const a of args) console.log(`${new Set(lex(readFileSync(resolve(cwd, a), 'utf8')).events.map((e) => e.line)).size}\t${a}`);
  process.exit(0);
}
const files = (args.length ? args.map((a) => relative(ROOT, resolve(cwd, a)).split(sep).join('/')) : listFiles())
  .filter((f) => !SKIPPED.test(f) && existsSync(join(ROOT, f)))
  .sort();
if (args.length && files.length !== args.length) {
  console.error('rust-source: a file named on the command line does not exist or is skipped');
  process.exit(2);
}
const domains = existsSync(join(ROOT, 'src'))
  ? readdirSync(join(ROOT, 'src')).filter((d) => !NOT_DOMAINS.has(d) && statSync(join(ROOT, 'src', d)).isDirectory())
  : [];
let checked = 0;
for (const path of files) {
  const src = readFileSync(join(ROOT, path), 'utf8');
  if (src.split('\n').slice(0, 5).some((l) => l.includes('@generated'))) continue;
  checked++;
  const lexed = lex(src);
  checkLines(path, lexed);
  checkAllow(path, lexed);
  const isTest = /^(tests|benches|examples)\//.test(path) || /_tests\.rs$/.test(path);
  if (isTest || !path.startsWith('src/')) continue;
  checkHandlers(path, lexed);
  checkRoutes(path, lexed);
  checkLayers(path, lexed, domains);
  checkSql(path, lexed);
}

if (findings.length) {
  for (const f of findings) console.error(f);
  console.error(`rust-source: ${findings.length} finding(s) in ${checked} file(s); the rules are in AGENTS.md`);
  process.exit(1);
}
console.log(`rust-source: ${checked} file(s); LINES HANDLERS ROUTES LAYERS SQL ALLOW clean`);
