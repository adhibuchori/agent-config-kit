/**
 * The OpenAPI document the app declares, built from `src/app.ts` without starting a server.
 *
 * Shared by scripts/generate/openapi.ts (`spec:export`), which writes it to openapi.json, and
 * scripts/check/openapi.ts, which builds it again and compares. Routes declared with
 * `createRoute` + `router.openapi()` reach the document; a plain `app.get()` does not, and that
 * is the gap the check exists to show.
 */

import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

interface DocumentBuilder {
  getOpenAPI31Document: (config: {
    openapi: string;
    info: { title: string; version: string };
  }) => unknown;
}

function isBuilder(value: unknown): value is DocumentBuilder {
  return (
    typeof value === 'object' &&
    value !== null &&
    'getOpenAPI31Document' in value &&
    typeof value.getOpenAPI31Document === 'function'
  );
}

/** Lib: buildDocument
 * The document `src/app.ts` declares, titled from package.json; null when the repo has no app.
 */
export async function buildDocument(root: string): Promise<Record<string, unknown> | null> {
  const entry = join(root, 'src/app.ts');
  if (!existsSync(entry)) return null;
  const mod: unknown = await import(pathToFileURL(entry).href);
  const exported = typeof mod === 'object' && mod !== null ? { ...mod } : {};
  const app: unknown =
    'app' in exported ? exported.app : 'default' in exported ? exported.default : undefined;
  if (!isBuilder(app)) {
    throw new Error('src/app.ts exports no OpenAPIHono app (as `app` or the default export)');
  }
  const pkg: unknown = existsSync(join(root, 'package.json'))
    ? JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'))
    : {};
  const field = (name: string, fallback: string): string => {
    const value =
      typeof pkg === 'object' && pkg !== null && name in pkg ? Reflect.get(pkg, name) : undefined;
    return typeof value === 'string' && value !== '' ? value : fallback;
  };
  const doc = app.getOpenAPI31Document({
    openapi: '3.1.0',
    info: { title: field('name', 'api'), version: field('version', '0.0.0') },
  });
  if (typeof doc !== 'object' || doc === null) throw new Error('the app built no OpenAPI document');
  return { ...doc };
}
