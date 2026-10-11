#!/usr/bin/env bun
/**
 * The OpenAPI document builds, describes at least one route, publishes the Problem contract, and
 * equals the committed openapi.json.
 *
 * A route mounted with a plain `app.get()` never reaches the document, and a document that builds
 * but describes nothing is how that shows. A stale committed copy is how a frontend generates a
 * client for routes that changed. Paths and components are compared by meaning; the `info` block
 * may differ, since the bootstrap registers its own. Skipped, and says so, in a repo with no
 * src/app.ts. `process.exit` because importing the app may open clients that keep it alive.
 *
 * The Problem contract (.claude/rules/common/error-codes.md) is what every client resolves a
 * failure by: `components.schemas.Problem` with the code list inline on `code` (frontends read the
 * enum there and follow no `$ref`), every code matching CODE below, and `type` as `format: uri`
 * carrying `x-problem-type-base`, the one base each problem's type is minted from. `about:blank`
 * never appears as a default, const or enum value: it would make every problem the same type.
 */

import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildDocument } from '../lib/openapi-document';
import { sortKeys } from '../lib/source-scan';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..');
const SPEC = join(ROOT, 'openapi.json');
/* A code needs no percent-encoding at the end of a type URI, and reads as a constant. */
const CODE = /^[A-Z][A-Z0-9_]*$/;

/** A member of a JSON object, or undefined for anything that is not one. */
function at(value: unknown, key: string): unknown {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
    ? Reflect.get(value, key)
    : undefined;
}

/* Why `base` cannot prefix a problem type: an absolute https URI with no query or fragment, ending
   in `/`, written exactly as a URL parser writes it back. The payload middleware, where adopted,
   checks the same at startup. */
function baseError(base: string): string | undefined {
  let url: URL;
  try {
    url = new URL(base);
  } catch {
    return 'is not an absolute URI';
  }
  if (url.protocol !== 'https:') return 'is not https';
  if (base.includes('?') || base.includes('#')) return 'carries a query or a fragment';
  if (!base.endsWith('/')) return 'does not end in /';
  if (url.href !== base) return `is not written as ${url.href}`;
  return undefined;
}

/* Every place inside the schema where `about:blank` is a default, a const or an enum value. */
function aboutBlank(value: unknown, path: string): string[] {
  if (Array.isArray(value)) return value.flatMap((item, i) => aboutBlank(item, `${path}[${i}]`));
  if (typeof value !== 'object' || value === null) return [];
  const found = ['default', 'const'].filter((key) => at(value, key) === 'about:blank');
  const values = at(value, 'enum');
  if (Array.isArray(values) && values.includes('about:blank')) found.push('enum');
  return [
    ...found.map((key) => `${path}.${key}`),
    ...Object.entries(value).flatMap(([key, child]) => aboutBlank(child, `${path}.${key}`)),
  ];
}

/** What the document's Problem schema breaks of the contract; empty when it holds. */
function problemContract(doc: Record<string, unknown>): string[] {
  const problem = at(at(at(doc, 'components'), 'schemas'), 'Problem');
  if (problem === undefined) {
    return ['components.schemas.Problem is missing: register the schema problem.ts builds'];
  }
  const failures: string[] = [];
  const code = at(at(problem, 'properties'), 'code');
  const codes = at(code, 'enum');
  if (!Array.isArray(codes) || codes.length === 0) {
    failures.push('Problem.code carries no inline enum: list ERROR_CODES on the property itself');
  } else {
    for (const value of codes) {
      if (typeof value !== 'string' || !CODE.test(value)) {
        failures.push(`Problem.code ${JSON.stringify(value)} does not match ${CODE.source}`);
      }
    }
  }
  const type = at(at(problem, 'properties'), 'type');
  if (at(type, 'format') !== 'uri') failures.push('Problem.type is not `format: uri`');
  const base = at(type, 'x-problem-type-base');
  if (typeof base !== 'string') {
    failures.push('Problem.type has no x-problem-type-base: publish PROBLEM_TYPE_BASE there');
  } else {
    const why = baseError(base);
    if (why) failures.push(`Problem.type x-problem-type-base "${base}" ${why}`);
  }
  for (const where of aboutBlank(problem, 'Problem')) {
    failures.push(`${where} is about:blank: every problem's type is the base plus its code`);
  }
  return failures;
}

let doc: Record<string, unknown> | null;
try {
  doc = await buildDocument(ROOT);
} catch (error) {
  console.error(
    `[check:openapi] ✗ the document did not build: ${error instanceof Error ? error.message : String(error)}`,
  );
  process.exit(1);
}
if (!doc) {
  console.log('[check:openapi] No src/app.ts: no app to describe; nothing to check.');
  process.exit(0);
}

const paths = typeof doc.paths === 'object' && doc.paths !== null ? Object.keys(doc.paths) : [];
if (paths.length === 0) {
  console.error(
    '[check:openapi] ✗ the document builds but describes no route: declare routes with createRoute and router.openapi()',
  );
  process.exit(1);
}

const broken = problemContract(doc);
if (broken.length > 0) {
  console.error(`[check:openapi] ✗ the Problem contract has ${broken.length} problem(s):`);
  for (const failure of broken) console.error(`  - ${failure}`);
  console.error('  See .claude/rules/common/error-codes.md.');
  process.exit(1);
}

const meaning = (value: Record<string, unknown>): string =>
  JSON.stringify(sortKeys({ paths: value.paths ?? {}, components: value.components ?? {} }));
if (!existsSync(SPEC)) {
  console.error(
    '[check:openapi] ✗ openapi.json is not committed: run bun run spec:export and commit it',
  );
  process.exit(1);
}
const committed: unknown = JSON.parse(readFileSync(SPEC, 'utf8'));
if (
  typeof committed !== 'object' ||
  committed === null ||
  meaning({ ...committed }) !== meaning(doc)
) {
  console.error(
    '[check:openapi] ✗ openapi.json is stale: run bun run spec:export and commit the result',
  );
  process.exit(1);
}
console.log(
  `[check:openapi] ✓ ${paths.length} path(s) in the document, the Problem contract holds, openapi.json is current.`,
);
process.exit(0);
