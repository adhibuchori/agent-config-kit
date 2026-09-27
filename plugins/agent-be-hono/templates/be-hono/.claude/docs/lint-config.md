# Why the lint and format configs say what they say

`.oxlintrc.json` and `.oxfmtrc.json` are plain JSON, so they carry no comments. The reasons behind
their choices live here. Both files are yours to edit: setup creates them once, and
`/agent-be-hono:sync --check` never reports your edits as drift.

## .oxlintrc.json rules

| Rule | Why |
| --- | --- |
| `no-await-in-loop` | AGENTS.md §H Rule 31/36: a query in a loop is the N+1 signature. Batch with `inArray()` or a join, or run independent work through `Promise.all`. |
| `typescript/no-floating-promises` (with `checkThenables`), `no-misused-promises`, `await-thenable` | AGENTS.md §H Rule 37: Drizzle query builders are thenables, so a dropped `await` type-checks and silently never runs. These three are type-aware: they only fire under `oxlint --type-aware` (see the `lint` script), which needs the `oxlint-tsgolint` devDependency. `checkThenables` is the point: it defaults to false, and without it a dropped `await` on a query builder (a thenable, not a Promise) passes silently. |
| `typescript/only-throw-error` | AGENTS.md §C Rule 11: every thrown value is a `DomainError` subclass or an `HTTPException`; `throw "string"` bypasses the whole error contract. |
| `no-restricted-properties` on `process.env` | AGENTS.md §F Rule 22: `src/env.ts` is the only file that reads raw env. It is turned back off for `env.ts` itself below. |

## .oxlintrc.json overrides

| Files | Why |
| --- | --- |
| `scripts/**`, `.github/scripts/**` | Developer and CI scripts, not application code. Their output is for a person at a terminal, so the logger `no-console` protects would be the wrong tool; they run outside the app, so `process.env` is theirs to read. |
| `src/env.ts`, `src/db/client/migrate.ts` | They bootstrap env vars before the logger exists, so `console` is the only option, and `env.ts` is by definition the file that reads `process.env`. |
| `src/test/config.ts` | The integration-test gate must answer before `env.ts` validates anything: importing `env.ts` here would make every unit test require `DATABASE_URL`. |
| `src/lib/errors/problem.ts` | It must narrow a plain number to `ContentfulStatusCode` to hand it to `c.body()`. No `any` here either: AGENTS.md §G Rule 42 has no exemption. |
| `src/lib/errors/errors.ts` | The pass-through constructors are deliberate; see the class-level comment in `errors.ts` on Bun's coverage attribution for field overrides. |
| `src/**/__tests__/**` | Tests build mocks by asserting plain objects into Hono and Drizzle types, and await deliberately synchronous fakes. Both are how a mock is written, not the defects these rules exist to catch; §H Rule 37 stays armed everywhere real queries run, and `any` stays an error in tests too (§G Rule 42). |
| `src/modules/*/*.service.ts` | AGENTS.md §B Rule 7: services are pure business logic and never see a Hono Context. Dependencies arrive as default parameters instead. |
| `src/modules/*/**` | A module is reached only through its `index.ts` barrel from outside itself. `../*/[!index]*` matches a path two or more levels into another module's internals; a same-module relative import (`../sibling.ts`, `./sibling.ts`) never has that second `/` segment, so it is unaffected. |
| `src/modules/*/*.handler.ts` | Handlers are thin HTTP glue. Database access belongs in the service (or the repository on escalation), never in a handler. |
| `src/lib/**`, `src/middlewares/**` | Infrastructure that modules depend on. The dependency direction never reverses. |

## .oxfmtrc.json

`scripts/check/coverage-policy.mjs` and `scripts/check/folder-shape.mjs` are in `ignorePatterns`:
the plugins install them and `sync --check` compares them with the plugins' copies, so a format
pass here would show as drift.
