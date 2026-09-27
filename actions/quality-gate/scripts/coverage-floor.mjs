#!/usr/bin/env node
// The quality gate's coverage floor: reads the newest coverage report under the given folders and
// fails when lines, statements, functions or branches fall below the threshold. Each metric counts
// only when the report measured it (bun measures no branches, for example).
//
//   node coverage-floor.mjs --threshold 100 <dir>...
//
// Reports, by file name (searched up to 4 folders deep; node_modules is skipped):
//   lcov.info              bun (coverageReporter "lcov"), vitest or jest with the lcov reporter
//   coverage-summary.json  istanbul json-summary reporter
//   coverage-final.json    istanbul json reporter (vitest's default reporters include it)
//
// Exit: 0 at or above the floor, 1 below it, 2 bad usage or an unreadable report, 3 no report found.
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

const NAMES = new Set(['lcov.info', 'coverage-summary.json', 'coverage-final.json']);
const MAX_DEPTH = 4;

function usage(message) {
  console.error(`coverage-floor: ${message}`);
  console.error('usage: coverage-floor.mjs --threshold <0-100> <dir>...');
  process.exit(2);
}

const argv = process.argv.slice(2);
let threshold = null;
const dirs = [];
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === '--threshold') {
    threshold = argv[++i];
  } else if (argv[i].startsWith('--threshold=')) {
    threshold = argv[i].slice('--threshold='.length);
  } else if (argv[i].startsWith('-')) {
    usage(`unknown option ${argv[i]}`);
  } else {
    dirs.push(argv[i]);
  }
}
if (threshold === null || !/^(100(\.0+)?|\d{1,2}(\.\d+)?)$/.test(threshold)) {
  usage('--threshold must be a number from 0 to 100');
}
if (dirs.length === 0) usage('name at least one folder to search');
const floor = Number(threshold);

function find(dir, depth, found) {
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const e of entries) {
    const p = join(dir, e.name);
    if (e.isDirectory()) {
      if (depth < MAX_DEPTH && e.name !== 'node_modules' && e.name !== '.git') find(p, depth + 1, found);
    } else if (e.isFile() && NAMES.has(e.name)) {
      found.push({ path: p, mtime: statSync(p).mtimeMs });
    }
  }
}

const found = [];
for (const d of dirs) find(d, 0, found);
if (found.length === 0) {
  console.log(`coverage-floor: no coverage report under ${dirs.join(', ')}`);
  process.exit(3);
}
// The newest report is the run that just happened; an older one is left over from a local run.
found.sort((a, b) => b.mtime - a.mtime || a.path.localeCompare(b.path));
const report = found[0].path;

const metric = () => ({ total: 0, covered: 0 });

function fromLcov(text) {
  const m = { lines: metric(), functions: metric(), branches: metric() };
  let da = null;
  let lf = null;
  let lh = null;
  for (const raw of text.split('\n')) {
    const line = raw.trim();
    const [key, value = ''] = line.split(/:(.*)/s);
    switch (key) {
      case 'SF':
        da = { total: 0, covered: 0 };
        lf = lh = null;
        break;
      case 'DA': {
        const hits = Number(value.split(',')[1]);
        da ??= { total: 0, covered: 0 };
        da.total += 1;
        if (hits > 0) da.covered += 1;
        break;
      }
      case 'LF': lf = Number(value); break;
      case 'LH': lh = Number(value); break;
      case 'FNF': m.functions.total += Number(value); break;
      case 'FNH': m.functions.covered += Number(value); break;
      case 'BRF': m.branches.total += Number(value); break;
      case 'BRH': m.branches.covered += Number(value); break;
      case 'end_of_record':
        // LF/LH when the tool wrote them, otherwise the DA lines.
        m.lines.total += lf ?? da?.total ?? 0;
        m.lines.covered += lh ?? da?.covered ?? 0;
        da = null;
        break;
      default:
        break;
    }
  }
  return m;
}

function fromSummary(json) {
  const t = json.total;
  if (!t) throw new Error('no "total" entry');
  const m = {};
  for (const k of ['lines', 'statements', 'functions', 'branches']) {
    if (t[k] && Number.isFinite(t[k].total)) m[k] = { total: t[k].total, covered: t[k].covered };
  }
  return m;
}

function fromFinal(json) {
  const m = { lines: metric(), statements: metric(), functions: metric(), branches: metric() };
  for (const file of Object.values(json)) {
    const s = file.s || {};
    const perLine = new Map();
    for (const [id, hits] of Object.entries(s)) {
      m.statements.total += 1;
      if (hits > 0) m.statements.covered += 1;
      const at = file.statementMap?.[id]?.start?.line;
      if (at !== undefined) perLine.set(at, Math.max(perLine.get(at) ?? 0, hits));
    }
    for (const hits of perLine.values()) {
      m.lines.total += 1;
      if (hits > 0) m.lines.covered += 1;
    }
    for (const hits of Object.values(file.f || {})) {
      m.functions.total += 1;
      if (hits > 0) m.functions.covered += 1;
    }
    for (const arms of Object.values(file.b || {})) {
      for (const hits of arms) {
        m.branches.total += 1;
        if (hits > 0) m.branches.covered += 1;
      }
    }
  }
  return m;
}

let metrics;
try {
  const text = readFileSync(report, 'utf8');
  if (report.endsWith('lcov.info')) metrics = fromLcov(text);
  else if (report.endsWith('coverage-summary.json')) metrics = fromSummary(JSON.parse(text));
  else metrics = fromFinal(JSON.parse(text));
} catch (err) {
  console.error(`coverage-floor: cannot read ${report}: ${err.message}`);
  process.exit(2);
}

const measured = Object.entries(metrics).filter(([, v]) => v.total > 0);
if (measured.length === 0) {
  console.error(`coverage-floor: ${report} measured nothing (0 lines, functions and branches)`);
  process.exit(2);
}

console.log(`coverage-floor: ${report} (floor ${floor}%)`);
let below = 0;
for (const [name, { total, covered }] of measured) {
  const pct = (covered * 100) / total;
  // Compare in integers: 99.995% must not round up to 100.
  const ok = covered * 100 >= floor * total;
  if (!ok) below += 1;
  console.log(`  ${name.padEnd(11)} ${String(covered).padStart(7)} / ${String(total).padEnd(7)} ${pct.toFixed(2).padStart(6)}%  ${ok ? 'ok' : 'BELOW'}`);
}
process.exit(below ? 1 : 0);
