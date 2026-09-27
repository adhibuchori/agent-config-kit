# Code Review Checklist

On-demand reference: CLAUDE.md lists it under **On-demand References**, and nothing imports it.
Where the repo has an `AGENTS.md`, a reviewer subagent checks its numbered rules mechanically; this
is the human checklist around it. `/agent-core:review` reads it, and `/agent-core:ship` fixes
what it finds down to MEDIUM.

The base below applies to every stack; skip a section the change cannot touch (a docs site runs no
queries). Each stack adds its own checks in the marked section at the end, citing its `AGENTS.md`
rules by number there, where it has them, rather than here.

## When to review

- After writing or modifying code
- Before any commit to a shared branch
- When the diff touches authentication, authorization, user data, the env schema, or anything that
  reads a secret
- When a query, schema or migration changes
- Before merging a pull request

**Before requesting review:** CI is green, conflicts are resolved, and the branch is up to date
with its target.

## Machine first

Run CLAUDE.md § Quality Gates before reading a line. The gates already fail on formatting, lint,
types, dead code, coverage, secrets and folder shape, so flagging those by hand is noise. Spend the
review on what no gate can see: behaviour, contracts, data access, and whether the change is
testable and honest about its failures.

## Checklist

**Boundaries and contract**

- [ ] Each layer does its own job: entry points (handlers, pages, CLI commands) stay thin glue, and
      logic lives where a unit test can reach it without a live service
- [ ] Cross-module access goes through the module's public entry, never into its internals
- [ ] Errors carry a code from the registry and are mapped in one place; no response leaks an ID, a
      path, a stack trace or an upstream provider's message
- [ ] Every status a route can return is declared, and every code a client can receive is mapped
- [ ] Every new route that changes state declares its auth guard explicitly

**Data and performance**

- [ ] Every list read is bounded and paginated; no deep `OFFSET` paging on a growing table
- [ ] Columns are selected explicitly on wide tables
- [ ] No query or remote call inside a loop, directly or through a helper
- [ ] Every newly filtered, sorted or joined column is indexed in the same change; foreign keys
      always
- [ ] Transactions hold only database work: no HTTP, no cache, no queue publish inside one
- [ ] Writes are batched; an upsert is a real upsert, not select-then-insert
- [ ] A new cache entry has a TTL and an invalidation path in the same change

**Tests**

- [ ] New logic ships with tests that meet the coverage rule (`.claude/rules/*/coverage.md`)
- [ ] A new guard's test was proven by mutating the guarded line and watching it fail
- [ ] No test replaces a module that the shared doubles own

**General**

- [ ] Readable and well named; files within the max-lines limit; nesting no deeper than 4 levels
- [ ] No lint-disable comments, no explicit `any`, no double assertion
- [ ] Every ignored error says why, in the code
- [ ] Docs and comments that describe the changed behaviour were updated with it

## Security review triggers

**Stop and read carefully when the diff touches:** authentication or authorization, user input
handling, raw SQL or template interpolation, a redirect, a shell command, a file path built from
input, an outbound request to a URL a user controls, anything that reads a secret, or the env
schema.

## Severity levels

| Level    | Meaning                                  | Action                                    |
| -------- | ---------------------------------------- | ----------------------------------------- |
| CRITICAL | Security vulnerability or data loss risk | **BLOCK** — must fix before merge         |
| HIGH     | Bug or significant quality issue         | **WARN** — should fix before merge        |
| MEDIUM   | Maintainability concern                  | **INFO** — fix now; `/agent-core:ship` does |
| LOW      | Style or minor suggestion                | **NOTE** — optional                       |

## Common issues to catch

**Security**

- Hard-coded credentials; environment read outside the one env module
- SQL injection: interpolation into a raw query outside the data-access layer
- Error responses leaking internals
- A new endpoint outside the rate limit or request budget the rest of the API sits behind
- CORS without an origin allowlist
- Unescaped user input rendered as HTML; path traversal; server-side requests to user-supplied URLs

**Correctness**

- An async call that is never awaited: it type-checks and silently discards its result
- A cache key missing an input that changes the answer
- A code-side fallback that turns a missing env key into a quiet wrong address instead of a crash
- A bare catch that swallows the failure; a blocking call on an async path

**Performance**

- N+1 access patterns
- Unbounded reads
- A cache added where an index was missing
- Heavy work repeated on every render or request that could be computed once

## Approval criteria

- **Approve** — no CRITICAL or HIGH issues
- **Warning** — only HIGH issues (merge with caution)
- **Block** — CRITICAL issues found

## Stack checks

<stack-block name="review-checks">

**Hono, Drizzle, Bun** — the `agent-be-hono:reviewer` subagent checks most of these mechanically;
read the query code yourself anyway.

- [ ] Handler is thin glue: ≤15 lines, no DB access, no try/catch for domain errors (§B Rule 6,
      §G Rule 28)
- [ ] Service is pure: no `Context`, dependencies as default parameters or steered through the
      shared test doubles (§B Rule 7)
- [ ] Cross-module imports go through `index.ts` (§B Rule 8); `lib/` and `middlewares/` never
      import from `modules/` (§B Rule 9)
- [ ] Every thrown error is a `DomainError` or an `HTTPException`, its code is in `ERROR_CODES`,
      and `userMessage` carries nothing internal (§C Rules 11–12)
- [ ] The route's `responses` map spreads `errorResponses(...)` for every status its service can
      throw, plus 422 (§C Rule 13)
- [ ] A schema change ships its generated migration in the same PR; a backfill is a replay-safe
      custom migration (§D Rule 16)
- [ ] Every list query has an explicit `.limit()` and the endpoint is keyset-paginated (§H Rule 29)
- [ ] Columns are selected explicitly on wide tables (§H Rule 30); no query in a loop, directly or
      through a helper (§H Rule 31)
- [ ] Every filtered, sorted or joined column is indexed in this change, foreign keys always
      (§H Rule 32); `bash scripts/check/index-coverage.sh` passes
- [ ] `EXPLAIN (ANALYZE, BUFFERS)` output is in the PR for a table expected past ~100k rows
      (§H Rule 33)
- [ ] Transactions hold only DB work (§H Rule 35); writes are batched and upserts use
      `onConflictDoUpdate` (§H Rule 36)
- [ ] Every Drizzle query is awaited, and the type-aware lint that catches a missing `await`
      actually ran (§H Rule 37)
- [ ] The pool keeps `statement_timeout`, `idle_in_transaction_session_timeout` and no cap of 1 or
      2 (§D Rule 17, §I Rule 38)
- [ ] CORS stays an allowlist (§I Rule 39); a new endpoint sits under `/api/*`, inside the request
      budget and the rate limit (§I Rule 41); a new log line in a request path carries
      `requestId` (§I Rule 40)
- [ ] A new service ships `__tests__/<module>.service.test.ts`; a unit test never imports the real
      database or Redis client (§E Rules 19–20); a route test goes through the real `app`
      (§E Rule 21)
- [ ] No explicit `any` and no double assertion (§G Rule 42); a literal another place must spell
      the same way is imported from `src/lib/constants/` (§G Rule 43)
- [ ] A new environment variable is read only in `src/env.ts` (§F Rule 22) and lands in
      `.env.<target>.example` and SSOT.md § Env Variables in the same change

- [ ] A route that needs a signed-in caller declares its guard on the route
      (`createRoute({ middleware: [...] })`). A path-scoped `use()` guard also catches a public
      GET that shares the path, or misses a route mounted beside it
- [ ] Where the payload contract is adopted: every new route is in the registry, with a reason when
      it is not `strict` (`.claude/PAYLOAD-CONTRACT.md`)

</stack-block>
