---
paths:
  - 'src/**'
---

# Common Patterns

The concrete, enforced version of everything here is `AGENTS.md`. This file names the patterns
this repo uses and points at where each one is specified.

## Reuse before writing

Before implementing anything non-trivial: check whether `src/modules/<reference-module>/` already
demonstrates the shape, check the package registry for a battle-tested library, and check the
vendor docs for the API's actual behavior. Prefer adopting a proven approach over net-new code —
but not at the cost of a dependency this repo does not need (`AGENTS.md` §A Rule 2).

## Architectural patterns in this repo

| Pattern | Where it is specified |
|---|---|
| Modular monolith — feature verticals with internal layering | `SSOT.md` §Architecture |
| `handler → service → db`, repository only on escalation | `AGENTS.md` §A Rule 4, §B Rule 5 |
| Dependency injection via default parameters (no container, no mocking library) | `AGENTS.md` §B Rule 7 |
| Module barrel — `index.ts` is a module's only public surface | `AGENTS.md` §B Rule 8 |
| One-way dependency direction: `modules/* → lib/*, db/*, middlewares/*` | `AGENTS.md` §B Rule 9 |
| RFC 9457 `application/problem+json` as the single error envelope | `AGENTS.md` §C, `src/lib/errors/problem.ts` |
| OpenAPI-first routing — the route declares the contract, including errors | `.claude/rules/backend/hono.md` |
| Keyset pagination as the default list contract | `AGENTS.md` §H Rule 29, `backend/drizzle.md` |
| Redis cache-aside, in the service, always with a TTL | `.claude/rules/backend/performance.md` |
| Transaction boundaries in the repository, never spread across a service | `AGENTS.md` §H Rule 35 |
| One home per shared literal, under `src/lib/constants/` | `AGENTS.md` §G Rule 43 |

## Patterns deliberately NOT used

- **A generic repository/base-class layer.** Repositories are added per module, only when
  Rule 4's escalation criteria are met.
- **A DI container.** Default parameters cover every case this repo has.
- **A shared `test-utils` package.** Mock builders stay module-local until real duplication
  proves otherwise (`backend/testing.md`). External clients are the exception: they are
  replaced once, in the shared doubles under `src/test/`.
- **Hand-rolled error envelopes.** There is exactly one, and `src/lib/errors/problem.ts` owns it.
