---
paths:
  - 'src/app.ts'
  - 'src/index.ts'
  - 'src/modules/**'
  - 'src/middlewares/**'
  - 'src/lib/server/factory.ts'
  - 'src/lib/errors/problem.ts'
---

# Hono + `@hono/zod-openapi` Patterns

`AGENTS.md` §B/§C (layer boundaries, error contract) and §I (Rules 38–41, runtime hardening)
are the enforced, numbered versions — read those first. This file is the deeper reference.

## Router creation

Never `new OpenAPIHono()` or `new Hono()` directly. Always `createRouter()` from
`src/lib/server/factory.ts` — it wires the shared `defaultHook` (422 problem+json) and the `AppEnv`
context type in one place:

```ts
import { createRouter } from "../../lib/server/factory.ts";
const thingRouter = createRouter();
```

## Route definition

`createRoute()` from `@hono/zod-openapi`, bound via `router.openapi(route, handler)`. The
route owns the OpenAPI contract — path, method, request schemas, and every response including
error responses:

```ts
export const getThingRoute = createRoute({
  method: "get",
  path: "/things/{id}",
  request: { params: z.object({ id: z.string() }) },
  responses: {
    200: { content: { "application/json": { schema: thingResponseSchema } }, description: "OK" },
    ...errorResponses(404, 422), // src/lib/errors/problem.ts
  },
});
```

Do not write a `HEAD` route. Hono answers HEAD by running the GET handler and stripping the
body; a dedicated HEAD handler never executes.

## Handlers

Typed `RouteHandler<typeof route, AppEnv>` — the second type parameter is required, or
`c.env` type-checks against Hono's bare `Env` instead of `AppEnv` and everything downstream
(`requestId`, session, future context vars) loses its type. `@hono/zod-openapi` supports this
fully — do not reach for `hono-openapi`'s `describeRoute()` + `as never` workaround; that's a
different library's typing gap that doesn't apply here.

```ts
export const getThing: RouteHandler<typeof getThingRoute, AppEnv> = async (c) => {
  const { id } = c.req.valid("param");
  const thing = await getThingById(id); // service call
  return c.json(thing, 200);
};
```

Handlers stay ≤15 lines (Rule 28) and never build a JSON error body by hand (Rule 11) — throw a
`DomainError` and let `app.onError` map it.

Do not build Rails-style controller classes. If a route needs shared middleware plus a handler,
compose them with `factory.createHandlers(...)` rather than inventing a controller layer — the
module's service is already the place logic lives.

## Middleware

`factory.createMiddleware()` from `src/lib/server/factory.ts`, never a bare `createMiddleware()` from
`hono/factory` — the shared factory is what carries `AppEnv`, and without it `c.get("requestId")`
and every future context variable type-check against Hono's empty `Env`.

## Middleware order in `app.ts` (Rule 41)

The order is part of the contract, not a preference. It is documented inline in `src/app.ts`;
the reasoning:

| Position | Middleware | Why here |
|---|---|---|
| 1 | `requestId()` | Everything below must be able to log the correlation id |
| 2 | `secureHeaders()` | Must be in place before any response body can be produced |
| 3 | `cors({ origin: env.CORS_ORIGINS })` | Reject a disallowed origin before spending work. **Never a bare `cors()`** — that sends `Access-Control-Allow-Origin: *` (Rule 39) |
| 4 | `requestLogger` | Correlation exists by now, so the log line carries it |
| 5 | `bodyLimit` (`/api/*`) | Reject an oversized payload before reading it |
| 6 | `timeout` (`/api/*`) | Cap total handler time |
| 7 | `rateLimiter` (`/api/*`) | Last, so a request already rejected above never consumes quota |

`bodyLimit`'s default `onError` throws an `HTTPException` carrying its own plain-text 413
`Response`, which `handleAppError` would render with a generic title — `app.ts` passes an
explicit `onError` that throws a message-only `HTTPException(413)` so the problem+json `detail`
stays meaningful. `timeout()` already throws a message-carrying 504, so it needs no equivalent.
Both land in `app.onError`, so the request budget does not punch a hole in the error contract.

`app.onError` and `app.notFound` are registered once, globally. Hono resolves them at request
time regardless of where they sit relative to route mounts, but keeping them visually above the
mounts keeps `app.ts` readable top-to-bottom as "policy, then routes".

## Caching and large responses

- For a response that is expensive to build and safe to revalidate, add `etag()` on that route
  group — Hono answers a matching `If-None-Match` with 304 and no body.
- Data-level caching (Redis cache-aside) belongs in the service, not in middleware; see
  `.claude/rules/backend/performance.md`.
- For a genuinely large payload, stream (`stream`/`streamText` from `hono/streaming`) rather
  than materializing the whole body — but first check whether the endpoint should have been
  paginated (Rule 29). Streaming an unbounded result set is still an unbounded read.

## OpenAPI spec generation

`app.doc("/openapi.json", {...})` is called once, in `src/index.ts` (bootstrap), not in
`app.ts` (composition) — the OpenAPI document metadata (title/version/description) is a
bootstrap concern, not part of the request-handling composition.

The spec and the reference UI (`/openapi.json`, `/docs`) need their own switch: an environment
flag that production sets to off unless they are meant to be public. Do not assume a proxy or an
access policy in front of them; check with an anonymous request after the deploy. The committed
`openapi.json` is exported with `bun run spec:export`, and `check:openapi` fails when it is stale or
describes no route.
