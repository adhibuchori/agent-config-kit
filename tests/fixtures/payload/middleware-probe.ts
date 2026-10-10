/**
 * Runs be-hono's payload middleware with no Hono installed, and fails on any difference from the
 * contract's wire answers: the exact plaintext refusal (the code, never the internal message) and
 * the `Vary` a sealed answer carries. Kit CI has Node and no Hono, so this is how the seeded
 * middleware is proven there.
 *
 *   bun tests/fixtures/payload/middleware-probe.ts <repo>
 *
 * <repo> holds src/lib/payload/ and src/middlewares/payload.middleware.ts as setup installs them,
 * and node_modules/hono/factory.js exporting `createMiddleware = (middleware) => middleware`, which
 * is all Hono's own does. The context below is the handful of members the middleware reads.
 */

import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { isDeepStrictEqual } from 'node:util';

interface ProbeContext {
  req: { url: string; method: string; raw: Request; header: (name: string) => string | undefined };
  res: Response;
  get: (key: string) => unknown;
}
type Middleware = (c: ProbeContext, next: () => Promise<void>) => Promise<Response | undefined>;

const repo = process.argv[2] ?? '.';
const load = (rel: string): Promise<unknown> => import(pathToFileURL(join(repo, rel)).href);
const { createPayloadMiddleware } = (await load('src/middlewares/payload.middleware.ts')) as {
  createPayloadMiddleware: (options: object) => Middleware;
};
const { createKeyRing } = (await load('src/lib/payload/key-ring.ts')) as {
  createKeyRing: (sources: { value: string; name: string }[]) => Promise<unknown>;
};
const { toBase64Url } = (await load('src/lib/payload/base64url.ts')) as {
  toBase64Url: (bytes: Uint8Array) => string;
};

/* Test-only key material: 32 bytes of one value, never a real key. */
const ring = await createKeyRing([
  { value: `k1:${toBase64Url(new Uint8Array(32).fill(5))}`, name: 'TEST_KEY' },
]);
const registry = {
  POST_NOTES: { method: 'POST', pattern: '/api/notes', encryption: 'strict' },
  GET_NOTES_BY_ID: { method: 'GET', pattern: '/api/notes/:id', encryption: 'strict' },
};
const middleware = createPayloadMiddleware({ mode: 'strict', registry, keyRing: async () => ring });

function context(method: string, path: string, init: RequestInit): ProbeContext {
  const url = `http://probe.invalid${path}`;
  const c: ProbeContext = {
    req: {
      url,
      method,
      raw: new Request(url, { method, ...init }),
      header: (name) => c.req.raw.headers.get(name) ?? undefined,
    },
    res: new Response(null, { status: 404 }),
    get: () => undefined,
  };
  return c;
}

const failures: string[] = [];

/* 1. A plaintext body on a sealed route is refused in plaintext, with exactly these members. */
const refusal = { type: 'about:blank', title: 'Payload refused', status: 400, code: 'ENVELOPE_REQUIRED' };
const plaintext = context('POST', '/api/notes', {
  headers: { 'content-type': 'application/json' },
  body: '{"title":"x"}',
});
const refused = await middleware(plaintext, async () => {
  failures.push('refusal: the route ran for a refused request');
});
if (!(refused instanceof Response)) {
  failures.push('refusal: the middleware answered nothing');
} else {
  if (refused.status !== 400) failures.push(`refusal: status ${refused.status}, expected 400`);
  const type = refused.headers.get('content-type');
  if (type !== 'application/problem+json') failures.push(`refusal: content-type ${type}`);
  const body: unknown = await refused.json();
  if (!isDeepStrictEqual(body, refusal)) {
    failures.push(`refusal: body ${JSON.stringify(body)}, expected ${JSON.stringify(refusal)}`);
  }
}

/* 2. A sealed answer varies on the request headers that chose its key. */
const sealing = context('GET', '/api/notes/7', { headers: { 'x-payload-kid': 'k1' } });
await middleware(sealing, async () => {
  sealing.res = Response.json({ id: '7' });
});
if (sealing.res.headers.get('content-type') !== 'application/vnd.payload-envelope+json') {
  failures.push('sealed answer: the body was not sealed');
}
const vary = sealing.res.headers.get('vary');
if (vary !== 'x-payload-epk, x-payload-kid') {
  failures.push(`sealed answer: Vary ${JSON.stringify(vary)}, expected "x-payload-epk, x-payload-kid"`);
}

if (failures.length > 0) {
  for (const failure of failures) console.error(`middleware-probe: ${failure}`);
  process.exit(1);
}
console.log('middleware-probe: the refusal is exact, and the sealed answer varies on its key headers');
