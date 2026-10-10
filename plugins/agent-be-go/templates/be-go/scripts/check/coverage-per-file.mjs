#!/usr/bin/env node
/**
 * Coverage per file: every measured file at 100%, in the metrics its toolchain reports.
 *
 * The quality gate's coverage floor reads totals; a file at 60% hides behind ninety at 100%. This
 * reads the same report file by file. `scripts/check/coverage.sh` runs it after the suite, and the
 * one list of exemptions is `scripts/check/coverage-exempt.txt` (rule: the language's coverage.md;
 * `scripts/check/coverage-policy.mjs` checks that list).
 *
 *   node scripts/check/coverage-per-file.mjs check <report>        lcov.info, or a Go cover profile
 *   node scripts/check/coverage-per-file.mjs ignore-regex           the exemptions as one regex, for
 *                                                                    llvm-cov's -ignore-filename-regex
 *   node scripts/check/coverage-per-file.mjs filter-go <raw> <out>  a Go cover profile without
 *                                                                    generated files and exemptions
 *
 * lcov.info (cargo llvm-cov, llvm-cov export -format=lcov): lines and functions, per `SF:` record.
 * A Go cover profile (go test -coverprofile): statements; a block that several test binaries
 * measured counts once, at its highest count. Go has no way to leave a file out, so `filter-go`
 * drops files whose header carries `// Code generated ... DO NOT EDIT.` and files the exemption
 * list names, before the check and the floor read the profile.
 *
 * Exemptions are `<glob>  # <reason>` lines, relative to the repo root: `*` stays in one folder,
 * `**` crosses folders, `?` is one character. A line without its reason is refused.
 *
 * Plain Node ESM with no dependencies. Exit 0 every file at 100%, 1 a file below it, 2 bad usage,
 * an unreadable report, or a report that measured no file at all.
 */
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..');
const EXEMPT = join(ROOT, 'scripts/check/coverage-exempt.txt');
const GENERATED = /^\/\/ Code generated .* DO NOT EDIT\.$/;

function fail(message) {
  console.error(`coverage-per-file: ${message}`);
  process.exit(2);
}

/** A glob as a POSIX extended regular expression (llvm-cov's dialect, and valid in JavaScript too). */
function globSource(glob) {
  let out = '';
  for (let i = 0; i < glob.length; ) {
    if (glob.startsWith('**/', i)) {
      out += '(.*/)?';
      i += 3;
    } else if (glob.startsWith('**', i)) {
      out += '.*';
      i += 2;
    } else {
      const c = glob[i];
      out += c === '*' ? '[^/]*' : c === '?' ? '[^/]' : c.replace(/[.+^${}()|[\]\\]/g, '\\$&');
      i += 1;
    }
  }
  return out;
}

/** The exemption globs; a line without `# reason` stops the run. */
function exemptions() {
  if (!existsSync(EXEMPT)) return [];
  const globs = [];
  readFileSync(EXEMPT, 'utf8')
    .split('\n')
    .forEach((raw, n) => {
      const line = raw.trim();
      if (line === '' || line.startsWith('#')) return;
      const hash = line.indexOf('#');
      if (hash < 0 || line.slice(hash + 1).trim() === '') {
        fail(`${relative(process.cwd(), EXEMPT)}:${n + 1}: "${line}" has no "# reason"`);
      }
      globs.push(line.slice(0, hash).trim());
    });
  return globs;
}

const repoPath = (p) => {
  const abs = resolve(ROOT, p);
  const rel = relative(ROOT, abs).split(sep).join('/');
  return rel.startsWith('..') ? p : rel;
};

/** Per-file totals from an lcov report: lines and functions; branches are left to the floor. */
function fromLcov(text) {
  const files = new Map();
  let current = null;
  for (const raw of text.split('\n')) {
    const line = raw.trim();
    if (line.startsWith('SF:')) {
      current = { lines: [0, 0], functions: [0, 0] };
      files.set(repoPath(line.slice(3)), current);
    } else if (current && line === 'end_of_record') {
      current = null;
    } else if (current) {
      const [key, value] = line.split(':');
      const n = Number(value);
      if (key === 'LF') current.lines[1] += n;
      else if (key === 'LH') current.lines[0] += n;
      else if (key === 'FNF') current.functions[1] += n;
      else if (key === 'FNH') current.functions[0] += n;
    }
  }
  return files;
}

/** Go's module path, so profile entries (import paths) map back to files in this repo. */
function goModule() {
  const mod = join(ROOT, 'go.mod');
  if (!existsSync(mod)) fail('go.mod not found at the repo root');
  const m = readFileSync(mod, 'utf8').match(/^module\s+(\S+)/m);
  if (!m) fail('go.mod has no module line');
  return m[1];
}

function goBlocks(text, source) {
  const lines = text.split('\n');
  if (!/^mode: (set|count|atomic)$/.test((lines[0] ?? '').trim())) fail(`${source} is not a Go cover profile (no "mode:" line)`);
  const blocks = new Map();
  for (const raw of lines.slice(1)) {
    const line = raw.trim();
    if (line === '') continue;
    const m = line.match(/^((.+\.go):\d+\.\d+,\d+\.\d+) (\d+) (\d+)$/);
    if (!m) fail(`${source}: unreadable profile line: ${line}`);
    const seen = blocks.get(m[1]);
    blocks.set(m[1], { file: m[2], stmts: Number(m[3]), count: Math.max(seen?.count ?? 0, Number(m[4])) });
  }
  return { mode: lines[0].trim(), blocks };
}

/** Per-file statement totals from a Go cover profile. */
function fromGoProfile(text, source) {
  const module = goModule();
  const files = new Map();
  for (const { file, stmts, count } of goBlocks(text, source).blocks.values()) {
    const path = file.startsWith(`${module}/`) ? file.slice(module.length + 1) : file;
    const t = files.get(path) ?? { statements: [0, 0] };
    t.statements[1] += stmts;
    if (count > 0) t.statements[0] += stmts;
    files.set(path, t);
  }
  return files;
}

function isGenerated(path) {
  let text;
  try {
    text = readFileSync(join(ROOT, path), 'utf8');
  } catch {
    return false;
  }
  for (const line of text.split('\n')) {
    if (GENERATED.test(line)) return true;
    if (/^package\s/.test(line)) return false;
  }
  return false;
}

function check(report) {
  if (!report) fail('usage: check <report>');
  let text;
  try {
    text = readFileSync(report, 'utf8');
  } catch (err) {
    fail(`cannot read ${report}: ${err.message}`);
  }
  const files = text.startsWith('mode: ') ? fromGoProfile(text, report) : fromLcov(text);
  if (files.size === 0) fail(`${report} measured no file; a coverage run that measured nothing is not a pass`);
  const below = [];
  for (const [path, t] of [...files].sort(([a], [b]) => (a < b ? -1 : 1))) {
    const parts = Object.entries(t).filter(([, [hit, total]]) => hit < total);
    if (parts.length) below.push(`  ${path}: ${Object.entries(t).map(([k, [hit, total]]) => `${k} ${hit}/${total}`).join(', ')}`);
  }
  const metrics = Object.keys(files.values().next().value).join(', ');
  if (below.length) {
    console.error(`coverage-per-file: ${below.length} of ${files.size} file(s) below 100% (${metrics}):`);
    console.error(below.join('\n'));
    console.error('Add the tests; a file is exempt only for a reason .claude/rules/<language>/coverage.md lists.');
    process.exit(1);
  }
  console.log(`coverage-per-file: ${files.size} file(s), each at 100% (${metrics})`);
}

function ignoreRegex() {
  const globs = exemptions();
  /* A path is never empty, so ^$ ignores nothing when nothing is exempt. */
  console.log(globs.length ? `(^|/)(${globs.map(globSource).join('|')})$` : '^$');
}

function filterGo(raw, out) {
  if (!raw || !out) fail('usage: filter-go <raw profile> <filtered profile>');
  let text;
  try {
    text = readFileSync(raw, 'utf8');
  } catch (err) {
    fail(`cannot read ${raw}: ${err.message}`);
  }
  const module = goModule();
  const exempt = exemptions().map((g) => new RegExp(`^${globSource(g)}$`));
  const { mode, blocks } = goBlocks(text, raw);
  const keep = [mode];
  const dropped = new Set();
  for (const [key, { file, stmts, count }] of blocks) {
    const path = file.startsWith(`${module}/`) ? file.slice(module.length + 1) : file;
    if (exempt.some((re) => re.test(path)) || isGenerated(path)) {
      dropped.add(path);
      continue;
    }
    keep.push(`${key} ${stmts} ${count}`);
  }
  writeFileSync(out, `${keep.join('\n')}\n`);
  console.log(`coverage-per-file: ${dropped.size} generated or exempt file(s) left out of ${out}`);
}

const [command, ...args] = process.argv.slice(2);
if (command === 'check') check(args[0]);
else if (command === 'ignore-regex') ignoreRegex();
else if (command === 'filter-go') filterGo(args[0], args[1]);
else fail('usage: coverage-per-file.mjs check <report> | ignore-regex | filter-go <raw> <out>');
