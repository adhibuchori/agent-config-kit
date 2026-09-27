#!/usr/bin/env bun
/**
 * MOCK — a module replacement must not reach the files that did not ask for one.
 *
 * `mock.module` in bun is process-wide and is never undone: the registration outlives the file that
 * made it and applies to every test file loaded afterwards. Which files those are is decided by the
 * order bun walks the tree, and that order differs between bun versions — so a leak of this kind
 * passes on one machine, fails on another, and is reproducible on both.
 *
 * It fails in two shapes (`.claude/anti-patterns/bun-mock-module-is-process-wide.md`):
 *
 *   1. A NARROWED surface. A test replaces a package with a factory that exports only the one
 *      function it needs. Every later file that imports anything else from that package gets
 *      `undefined`, and a module that calls one of those exports at load time stops loading.
 *   2. A COMPLETE surface with stubbed BEHAVIOUR. A test replaces a repository or a client, and a
 *      later file that expected the shared double reads the first file's leftover stub instead: its
 *      assertions pass or fail by file order.
 *
 * Only the second shape is fixable by spreading, so the rule is not "spread it": the shared doubles
 * in `src/test/` are the one place a module may be replaced, because they are installed once at
 * preload for the whole run and every file is written expecting them.
 *
 * Four checks, any of which fails the gate:
 *
 *   T0 — every `mock.module(` call names its module with a string literal. A specifier held in a
 *        variable cannot be matched against the allowlist, so it would slip past T1 unseen.
 *   T1 — no `mock.module` in a test file, unless the file:specifier pair is allowlisted.
 *   T2 — an allowlisted factory spreads the real module, so the allowlist cannot admit shape 1.
 *   T3 — every allowlisted pair was actually seen. An allowlist row that matches nothing means the
 *        scanner stopped finding calls, and a scanner that finds nothing reports a clean run
 *        (`.claude/anti-patterns/a-check-that-matches-nothing-passes.md`).
 *
 * The rule is the shared-doubles paragraph under AGENTS.md Rule 7 and
 * `.claude/rules/backend/testing.md`; `.claude/test-preload.example.ts` shows the doubles.
 */

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..');
const SRC = join(ROOT, 'src');

/**
 * `file:specifier` pairs permitted to replace a module, each with the reason it is safe.
 *
 * A third-party specifier whose real exports are spread through is the only shape that qualifies:
 * nothing is taken away from a later file, and the one overridden function belongs to the module
 * under test. Adding a row here is a decision about the whole run, not about one file. Shape:
 *
 *   ['src/lib/<area>/__tests__/<name>.test.ts:<package>', '<why nothing else can observe it>'],
 */
const ALLOWED = new Map<string, string>([]);

const failures: string[] = [];

function collectTestFiles(dir: string, isRoot = false): string[] {
  const out: string[] = [];
  let entries: string[];
  try {
    entries = readdirSync(dir);
  } catch (error) {
    /* Swallowing this at the root turns "src/ is unreadable" into "no test files found", and the
       check then passes on a tree it never read. A nested directory may legitimately vanish. */
    if (isRoot) throw error;
    return out;
  }
  for (const entry of entries) {
    if (entry === 'node_modules') continue;
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) out.push(...collectTestFiles(full));
    else if (/\.test\.tsx?$/.test(entry)) out.push(full);
  }
  return out;
}

const testFiles = collectTestFiles(SRC, true);

console.log(`Module mocks: scanning ${testFiles.length} test file(s)...`);

/*
 * Zero files is not "nothing to check" — it is the check unable to run. A filter that stops
 * matching, or a checkout that left src/ empty, looks exactly like a clean result otherwise.
 */
if (testFiles.length === 0) {
  console.error('\nModule mocks: no test files under src/ — the rule cannot be verified.\n');
  process.exit(1);
}

/* Every call site, then the ones whose specifier is a literal. The factory is read by balancing
   parens from the call rather than by a second pattern: a factory ends in `}))`, `})` or `});`
   depending on how it was written, and a pattern guessing which silently matches nothing. */
const ANY_CALL = /\bmock\.module\s*\(/g;
const CALL = /\bmock\.module\s*\(\s*['"]([^'"]+)['"]/g;

/**
 * The argument list of the `mock.module(` call starting at `index`, paren-balanced.
 *
 * Returns the text between the opening paren and its match, so T2 can look for the spread without
 * assuming anything about how the factory was formatted.
 */
function factoryAfter(content: string, index: number): string {
  const open = content.indexOf('(', index);
  if (open === -1) return '';
  let depth = 0;
  for (let i = open; i < content.length; i += 1) {
    const character = content[i];
    if (character === '(') depth += 1;
    else if (character === ')') {
      depth -= 1;
      if (depth === 0) return content.slice(open + 1, i);
    }
  }
  /* Unbalanced means the file does not parse, which tsc and oxlint both catch first. Returning the
     tail keeps T2 conservative rather than letting an unreadable factory pass as spread. */
  return content.slice(open + 1);
}

const seen = new Set<string>();
let calls = 0;

for (const file of testFiles) {
  const rel = relative(ROOT, file);
  const content = readFileSync(file, 'utf-8');
  const literal = [...content.matchAll(CALL)];
  const total = [...content.matchAll(ANY_CALL)].length;
  calls += total;

  /* ── T0 — every call is one this check can read ─────────────────────────────── */
  if (total !== literal.length) {
    failures.push(
      `${rel} has ${total - literal.length} mock.module call(s) whose module is not a string literal\n` +
        `    Fix: name the module inline, or better, steer the shared doubles in src/test/. (MOCK T0)`,
    );
  }

  for (const match of literal) {
    const specifier = match[1];
    const factory = factoryAfter(content, match.index);
    const key = `${rel}:${specifier}`;
    const reason = ALLOWED.get(key);
    seen.add(key);

    if (!reason) {
      failures.push(
        `${rel} replaces '${specifier}'\n` +
          `    Fix: steer the shared doubles in src/test/ instead — the <client>Control objects\n` +
          `    installed at preload for the whole run. A module replaced here stays replaced for\n` +
          `    every file bun loads after this one. (MOCK T1)`,
      );
      continue;
    }

    if (!factory.includes('...')) {
      failures.push(
        `${rel} is allowed to replace '${specifier}' but its factory spreads nothing\n` +
          `    Fix: read the real module first and spread it, overriding only what this file\n` +
          `    steers. Every export left out becomes undefined in every later file. (MOCK T2)`,
      );
    }
  }
}

/* ── T3 — the allowlist describes calls that are really there ───────────────── */
for (const [key, reason] of ALLOWED) {
  if (seen.has(key)) continue;
  failures.push(
    `${key} is allowlisted but no such call was found\n` +
      `    Reason on file: ${reason}\n` +
      `    Fix: if the mock is genuinely gone, delete the row. If it is still in the file, this\n` +
      `    check has stopped seeing it and every other call is unchecked too. (MOCK T3)`,
  );
}

if (failures.length > 0) {
  console.error(`\nModule mocks: ${failures.length} problem(s)\n`);
  for (const failure of failures) console.error(`  ✗ ${failure}\n`);
  process.exit(1);
}

/* What was scanned, not what was configured: the allowlist size alone says nothing about the run. */
console.log(
  `Module mocks: ${testFiles.length} test file(s), ${calls} mock.module call(s), ` +
    `${ALLOWED.size} allowlisted; all checks passed`,
);
