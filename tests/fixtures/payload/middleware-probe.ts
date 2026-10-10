/**
 * Runs be-hono's payload refusal and middleware with no Hono installed, and fails on any difference
 * from the contract's wire answers: the exact plaintext refusal (a type minted from the code, the
 * code's title, the request id, never the internal message), the `Vary` a sealed answer carries,
 * and a problem-type base refused at startup. Kit CI has Node and no Hono, so this is how the
 * seeded code is proven there.
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
const { payloadRefusal } = (await load('src/lib/payload/refusal.ts')) as {
  payloadRefusal: (base: string, status: number, code: string, requestId?: string) => Response;
};
const { createKeyRing } = (await load('src/lib/payload/key-ring.ts')) as {
  createKeyRing: (sources: { value: string; name: string }[]) => Promise<unknown>;
};
const { toBase64Url } = (await load('src/lib/payload/base64url.ts')) as {
  toBase64Url: (bytes: Uint8Array) => string;
};

/* The kit's placeholder base. Test-only key material: 32 bytes of one value, never a real key. */
const BASE = 'https://example.invalid/problems/';
const ring = await createKeyRing([
  { value: `k1:${toBase64Url(new Uint8Array(32).fill(5))}`, name: 'TEST_KEY' },
]);
const registry = {
  POST_NOTES: { method: 'POST', pattern: '/api/notes', encryption: 'strict' },
  GET_NOTES_BY_ID: { method: 'GET', pattern: '/api/notes/:id', encryption: 'strict' },
};
const options = { mode: 'strict', problemTypeBase: BASE, registry, keyRing: async () => ring };
const middleware = createPayloadMiddleware(options);

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
    get: (key) => (key === 'requestId' ? 'req-1' : undefined),
  };
  return c;
}

const failures: string[] = [];

async function expectProblem(where: string, response: unknown, expected: object): Promise<void> {
  if (!(response instanceof Response)) {
    failures.push(`${where}: no response`);
    return;
  }
  const status = Reflect.get(expected, 'status');
  if (response.status !== status) failures.push(`${where}: status ${response.status}, not ${status}`);
  const type = response.headers.get('content-type');
  if (type !== 'application/problem+json') failures.push(`${where}: content-type ${type}`);
  const body: unknown = await response.json();
  if (!isDeepStrictEqual(body, expected)) {
    failures.push(`${where}: body ${JSON.stringify(body)}, expected ${JSON.stringify(expected)}`);
  }
}

/* 1. The builder alone: the type is the base plus the code, the title the code's, and no more. */
await expectProblem('refusal.ts', payloadRefusal(BASE, 500, 'ENVELOPE_MALFORMED'), {
  type: `${BASE}ENVELOPE_MALFORMED`,
  title: 'Malformed envelope',
  status: 500,
  code: 'ENVELOPE_MALFORMED',
});

/* 2. A plaintext body on a sealed route, through the middleware, with the request id. */
const plaintext = context('POST', '/api/notes', {
  headers: { 'content-type': 'application/json' },
  body: '{"title":"x"}',
});
const refused = await middleware(plaintext, async () => {
  failures.push('refusal: the route ran for a refused request');
});
await expectProblem('refusal', refused, {
  type: `${BASE}ENVELOPE_REQUIRED`,
  title: 'Sealed body required',
  status: 400,
  code: 'ENVELOPE_REQUIRED',
  requestId: 'req-1',
});

/* 3. A sealed answer varies on the request headers that chose its key. */
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

/* 4. A base that cannot prefix a type stops the middleware from being built at all. */
try {
  createPayloadMiddleware({ ...options, problemTypeBase: 'about:blank' });
  failures.push('startup: problemTypeBase "about:blank" was accepted');
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  if (!message.includes('problemTypeBase "about:blank"')) failures.push(`startup: ${message}`);
}

if (failures.length > 0) {
  for (const failure of failures) console.error(`middleware-probe: ${failure}`);
  process.exit(1);
}
console.log(
  'middleware-probe: refusals are exact and minted from the code, sealed answers vary on their key headers, a bad base is refused',
);
