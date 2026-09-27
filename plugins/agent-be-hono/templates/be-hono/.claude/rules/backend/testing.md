---
paths:
  - 'src/**/__tests__/**'
  - 'src/test/**'
  - 'bunfig.toml'
---

# Backend Testing Conventions

Two tiers, both on Bun's built-in runner (`bunfig.toml` scopes discovery to `src/`). See
`AGENTS.md` §E for the enforced, numbered rules — this file is the deeper reference.

> **Every external client is replaced once, in `src/test/preload.ts`, never per test file.**
> `mock.module` mutates a registry shared by the whole run, so two files mocking the same module
> is last-write-wins and the loser silently inherits the other's mock — or makes a real network
> call. `bunfig.toml` wires the preload; `.claude/test-preload.example.ts` is the starting point
> (copy it to `src/test/preload.ts` and delete the clients your repo does not have). Steer through
> the controls it exports (`providerControl`, `redisControl`, `dbControl`, `authControl`), reset
> with `resetExternalMocks()` in `beforeEach`, and let `bun run check:mocks` refuse a per-file
> replacement. Why: `.claude/anti-patterns/bun-mock-module-is-process-wide.md`.

## Unit tests — `bun test src`

- Co-located under each module's `__tests__/`, named `<unit>.test.ts`.
- No real Postgres, no real Redis, no network. Services take their dependencies as default
  parameters (see `AGENTS.md` §B Rule 7); tests override them with a plain object, or steer the
  shared doubles.
- Module-local mock builders in `__tests__/helpers.ts`, named `create<Thing>Mock(overrides)`.
  Keep helpers module-local until real duplication across modules justifies a shared helper —
  do not build a generic `test-utils` package speculatively (`AGENTS.md` §A Rule 2).
- A double refuses what the real client refuses. A queue double that accepts any job id passes a
  producer that cannot enqueue (`.claude/anti-patterns/queue-job-id-cannot-contain-colon.md`).

```ts
// src/modules/health/__tests__/helpers.ts — an example
export function createDbMock(overrides: Partial<DbLike> = {}): DbLike {
  return { execute: async () => undefined, ...overrides };
}
```

## Integration tests — `bun run test:integration`

- File suffix `*.integration.test.ts`.
- Gated by `shouldRunIntegrationTests()` (`src/test/config.ts`), which reads
  `RUN_INTEGRATION_TESTS=1`:

```ts
import { test } from "bun:test";
import { shouldRunIntegrationTests } from "../../test/config.ts";

const testIntegration = shouldRunIntegrationTests() ? test : test.skip;
testIntegration("does the real thing against Postgres", async () => { /* ... */ });
```

- Requires `docker compose up -d` locally (Postgres 17 + Redis 7), with ports published on
  `127.0.0.1` only. The quality gate runs the unit tier alone; add a CI job with service
  containers when this tier has tests worth running there.
- Isolate fixtures with UUID-suffixed IDs so parallel test files (or reruns) don't collide on
  the same row.

## Query tests

Anything that runs SQL is integration-tier by definition — a unit test cannot tell you whether
an index is used or a transaction commits.

For a query whose *shape* matters (Rule 32: it was written against a specific index), assert the
generated SQL directly. That test runs in the unit tier and fails the moment someone reorders an
`ORDER BY` or drops a `WHERE` clause the index depended on:

```ts
const { sql, params } = buildThingPageQuery(cursor).toSQL();
expect(sql).toContain('order by "created_at" desc, "id" desc');
expect(params).toEqual([cursor, 51]);
```

Pair it with an integration test that runs the query against real Postgres for correctness.

## Route-level tests

Use `app.request(...)` against the real exported `app` (`src/app.ts`). Import the real
`handleAppError` indirectly through `app.onError` rather than asserting against a hand-rolled
error shape — a route test that redeclares its own error mapper can pass while the real
mapping has drifted. A library hook (an auth library's `hooks.after`, a plugin) is tested the same
way: through the library's own API or over HTTP, never by calling the hook function directly
(`.claude/anti-patterns/better-auth-user-hook-runs-first.md`).

## Coverage

`bun run test:coverage` runs `bun test src --coverage`, then `scripts/check/coverage-files.mjs`,
which fails on any source file no test loads (bun leaves those out of its report instead of showing
them at 0%). The threshold is 100% per file for lines and functions; bun measures no branches, so
a guard needs its own test even when its line runs on the happy path. The exemptions in
`bunfig.toml` are a closed list, each under its reason, and `.claude/rules/typescript/coverage.md`
names the categories.
