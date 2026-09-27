---
paths:
  - 'src/modules/**'
  - 'src/db/**'
  - 'src/lib/**'
  - 'src/middlewares/**'
---

# Backend Performance

The runtime budget and the caching patterns behind `AGENTS.md` §H (Rules 29–37) and §I
(Rules 38–41). Query-shape specifics live in `drizzle.md`; HTTP-layer specifics in `hono.md`.

## The request budget

Every `/api/*` request runs inside three limits, all set in `src/app.ts` and
`src/db/client/index.ts` from `src/env.ts`:

| Limit | Default | What it protects |
|---|---|---|
| `BODY_LIMIT_BYTES` | 1 MiB | Memory — an oversized body is rejected before it is read |
| `REQUEST_TIMEOUT_MS` | 15s | The handler as a whole (504) |
| `DB_STATEMENT_TIMEOUT_MS` | 10s | One query. Deliberately **below** the request timeout, so a slow query surfaces as a query failure rather than an opaque gateway timeout |
| `idle_in_transaction_session_timeout` | 30s | An abandoned transaction holding row locks |

If an endpoint genuinely needs longer than the request timeout, it is a job, not a request.

## N+1 checklist

Before merging any handler that touches more than one row:

- [ ] No `await` inside a `for`/`while`/`.map()` over database work — `no-await-in-loop` catches
      the common shape, but it cannot see a helper function that queries and is called in a loop.
- [ ] Related data comes from one statement: `inArray()`, a join, or RQB `with:` (which Drizzle
      emits as `LEFT JOIN LATERAL` + `json_agg`, a single query).
- [ ] Independent I/O runs concurrently through `Promise.all`, the way a health check runs
      `Promise.all([checkDatabase(...), checkRedis(...)])`.
- [ ] Every list query has an explicit `.limit()`.
- [ ] Every column in a `WHERE`, `ORDER BY`, or `ON` clause is indexed (Rule 32).

`Promise.all` is for *independent* work. Two queries where the second needs the first's result
are sequential by nature — the fix there is one query, not concurrency.

## Cache-aside with Redis

Caching belongs in the service, never in middleware — middleware cannot know which reads are
safe to serve stale.

```ts
// Key: <app>:<entity>:<version>:<id>. The version segment lets a shape change
// invalidate every old entry at once instead of hunting them down. The prefix is
// a shared identifier, so it lives in src/lib/constants/ (AGENTS.md Rule 43).
const cacheKey = `${CACHE_KEYS.thing}:${id}`; // "app:thing:v1"

const cached = await redis.get(cacheKey);
// A cached value is data from outside this process: parse it, never cast it (Rule 42).
if (cached) return thingSchema.parse(JSON.parse(cached));

const thing = await findThingById(id);
// Always set a TTL. A cache entry with no expiry is a memory leak with extra
// steps, and it turns a schema change into a permanent wrong answer.
await redis.set(cacheKey, JSON.stringify(thing), "EX", 300);
return thing;
```

Rules that make this safe:

- **Never cache without a TTL.**
- **Invalidate on write, in the same service function that performs the write** — a `del` that
  lives somewhere else will be forgotten.
- **A cache miss must never be an error.** Redis being down degrades latency, not correctness;
  the read falls through to Postgres. This mirrors how `rate-limit.middleware.ts` fails open.
- **Never cache anything scoped to a user under a key that is not.** The key must contain every
  input that changes the answer.
- **Do not cache to paper over a missing index.** Fix the query first; a cache in front of a
  sequential scan just moves the outage to the first cold start.

## Logging cost

Pino is fast, but a log line is still work. In a hot path log the fields, not a formatted
string, and never serialize a whole row into a log line — `logger.info({ requestId, thingId },
"…")`, not `logger.info(\`… ${JSON.stringify(thing)}\`)`. `AGENTS.md` §C Rule 12 already forbids
internals in `userMessage`; the same judgement applies to what is worth writing to disk on every
request.

## Measuring before optimizing

- Query shape: `query.toSQL()`, then `EXPLAIN (ANALYZE, BUFFERS)` (Rule 33).
- Endpoint latency: the `duration` field `requestLogger` already writes on every request,
  correlated by `requestId`.
- Do not add a cache, a prepared statement, or a denormalized column without a measurement
  showing which of the three the problem actually is. `AGENTS.md` §A Rule 2 (simplicity first)
  applies to performance work more than anywhere else — most slow endpoints here will be a
  missing index, and every other fix is more expensive to maintain than the index.
