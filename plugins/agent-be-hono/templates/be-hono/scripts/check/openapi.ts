#!/usr/bin/env bun
/**
 * The OpenAPI document builds, describes at least one route, and equals the committed openapi.json.
 *
 * A route mounted with a plain `app.get()` never reaches the document, and a document that builds
 * but describes nothing is how that shows. A stale committed copy is how a frontend generates a
 * client for routes that changed. Paths and components are compared by meaning; the `info` block
 * may differ, since the bootstrap registers its own. Skipped, and says so, in a repo with no
 * src/app.ts. `process.exit` because importing the app may open clients that keep it alive.
 */

import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildDocument } from '../lib/openapi-document';
import { sortKeys } from '../lib/source-scan';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..');
const SPEC = join(ROOT, 'openapi.json');

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
  `[check:openapi] ✓ ${paths.length} path(s) in the document, and openapi.json is current.`,
);
process.exit(0);
