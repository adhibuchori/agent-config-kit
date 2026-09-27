#!/usr/bin/env bun
/**
 * Writes the OpenAPI document the app declares to openapi.json (`bun run spec:export`).
 *
 * The committed file is what a frontend generates its client from and what the endpoint registry
 * is derived from, so it is regenerated, never edited. `check:openapi` rebuilds it and fails when
 * the committed copy is stale. `process.exit` at the end: importing the app may open a database or
 * cache client that would otherwise keep this one-off script alive.
 */

import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildDocument } from '../lib/openapi-document';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..');

const doc = await buildDocument(ROOT);
if (!doc) {
  console.error('spec:export: no src/app.ts to build the document from.');
  process.exit(1);
}
writeFileSync(join(ROOT, 'openapi.json'), `${JSON.stringify(doc, null, 2)}\n`);
console.log('spec:export: wrote openapi.json');
process.exit(0);
