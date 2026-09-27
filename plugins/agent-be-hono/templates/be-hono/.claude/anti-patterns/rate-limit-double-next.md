# `await next()` inside a middleware's own try/catch

**Applies to:** Any Hono middleware that wraps setup logic and `await next()` in the same
try/catch (this repo: `src/middlewares/rate-limit.middleware.ts`)
**Status:** A standing trap — kept as a reference so it isn't reintroduced into
`src/middlewares/rate-limit.middleware.ts` or any middleware shaped like it

## Symptom

Two distinct failure modes, both hard to spot in a code review that only skims the happy path:

1. A handler downstream of the middleware throws a real error (e.g. a domain error, a bug) —
   instead of reaching `app.onError`, it gets caught by the middleware's `catch` block, logged
   as "error in rate-limiting middleware," and then `next()` is called a SECOND time from the
   catch handler, re-running the rest of the middleware chain and the handler again.
2. Because the catch block's `await next()` is the fallback path, any transient failure inside
   the middleware itself (e.g. a Redis network blip that happens to occur while the response is
   being sent) can trigger the handler to run twice for one incoming request.

## Root Cause

```ts
// WRONG — await next() lives inside the try
try {
  const current = await redis.get(key);
  // ... rate limit bookkeeping ...
  await next(); // <- if this throws, we jump to catch below
} catch (error) {
  logger.error({ error }, "rate limit error");
  await next(); // <- runs AGAIN if the first next() partially executed then threw
}
```

`next()` calls into the rest of the middleware chain and the handler. Nothing about a handler
throwing an error is a "rate-limiting middleware error" — but putting `next()` inside the same
try/catch as the Redis calls conflates the two. The catch block's job (fail open on a Redis
outage) and the handler's job (run the actual request) get merged into one code path.

## Fix

Only the Redis bookkeeping goes in the try/catch. The allow/deny decision is resolved from that
try/catch's outcome, then `next()` runs exactly once, unconditionally, outside it:

```ts
let allowed = true;
try {
  // ... redis.get / redis.multi() / decide `allowed` ...
} catch (error) {
  // Redis is down — fail open rather than take the API down over a cache outage.
  logger.error({ error }, "rate-limit middleware error; failing open");
}

if (!allowed) {
  throw new HTTPException(429, { message: "Too many requests." });
}

await next(); // exactly once, regardless of which path above ran
```

## When to revisit

Never — this is a correct middleware shape regardless of what the middleware does. Any future
middleware with a "fail open on infra error" requirement should follow the same shape: decide
inside try/catch, act (throw or call `next()`) outside it.
