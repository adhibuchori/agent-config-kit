#!/usr/bin/env node
/**
 * Every source file must be loaded by at least one test.
 *
 * Bun's coverage report lists only the files a test imported. A module no test touches is absent
 * rather than at 0 %, so `coverageThreshold` never sees it: a handler with no test at all passes the
 * gate. This closes that hole, as `coverage.include` does for vitest and `source =` for coverage.py.
 *
 * Reads the lcov report `bun test --coverage` writes (bunfig.toml: coverageReporter, coverageDir),
 * then compares its `SF:` lines against `git ls-files src`, minus the test files and minus
 * `coveragePathIgnorePatterns` from bunfig.toml, the one list of exemptions. The rule is
 * `.claude/rules/typescript/coverage.md`; `test:coverage` in package.json runs this after the
 * suite.
 *
 * usage: node scripts/check/coverage-files.mjs [lcov path, default coverage/lcov.info]
 */
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

/* The lcov path is read from the caller's directory; everything else from the repo root, so a run
   from another folder cannot turn `git ls-files src` into an empty list and a vacuous pass. */
const lcovPath = resolve(process.argv[2] ?? 'coverage/lcov.info');
const root = join(dirname(fileURLToPath(import.meta.url)), '../..');
process.chdir(root);

if (!existsSync(lcovPath)) {
  console.error(`coverage-files: ${lcovPath} not found — run \`bun run test:coverage\` first.`);
  process.exit(2);
}

/** The string entries of `coveragePathIgnorePatterns = [ ... ]`, comments skipped. */
function ignorePatterns() {
  const toml = readFileSync('bunfig.toml', 'utf8');
  const block = toml.match(/coveragePathIgnorePatterns\s*=\s*\[([\s\S]*?)\]/);
  if (!block) return [];
  return block[1]
    .split('\n')
    .map((line) => line.replace(/#.*$/, ''))
    .flatMap((line) => [...line.matchAll(/"([^"]+)"/g)].map((m) => m[1]));
}

/** `**` crosses folders, `*` stays inside one. Anchored at both ends. */
function globToRegExp(glob) {
  let out = '';
  for (let i = 0; i < glob.length; i++) {
    const ch = glob[i];
    if (ch === '*' && glob[i + 1] === '*') {
      out += glob[i + 2] === '/' ? '(?:.*/)?' : '.*';
      i += glob[i + 2] === '/' ? 2 : 1;
    } else if (ch === '*') out += '[^/]*';
    else out += ch.replace(/[.+?^${}()|[\]\\]/g, '\\$&');
  }
  return new RegExp(`^${out}$`);
}

const ignored = ignorePatterns().map(globToRegExp);
const loaded = new Set(
  readFileSync(lcovPath, 'utf8')
    .split('\n')
    .filter((line) => line.startsWith('SF:'))
    .map((line) => line.slice(3).replace(`${root}/`, '').replace(`${process.cwd()}/`, '')),
);

const tracked = execFileSync('git', ['ls-files', 'src'], { encoding: 'utf8' })
  .split('\n')
  .filter((f) => /\.tsx?$/.test(f));

/* No TypeScript under src/ at all is the check unable to run (a sparse checkout, the wrong folder),
   not a clean result. */
if (tracked.length === 0) {
  console.error(
    'coverage-files: git ls-files found no TypeScript under src/ — nothing was checked.',
  );
  process.exit(1);
}

const sources = tracked
  .filter((f) => !f.includes('/__tests__/') && !/\.test\.tsx?$/.test(f))
  .filter((f) => !ignored.some((re) => re.test(f)));

const missing = sources.filter((f) => !loaded.has(f));
if (missing.length > 0) {
  console.error(`coverage-files: ${missing.length} source file(s) no test loads:`);
  for (const f of missing) console.error(`  ${f}`);
  console.error(
    'Write a test that imports each one, or — only if it is a barrel, a declaration, generated\n' +
      'output or composition wiring — add it to coveragePathIgnorePatterns in bunfig.toml with the\n' +
      'reason. See .claude/rules/typescript/coverage.md.',
  );
  process.exit(1);
}
console.log(
  `coverage-files: all ${sources.length} measured source file(s) are loaded by a test ` +
    `(${tracked.length - sources.length} test or exempt file(s) not measured).`,
);
