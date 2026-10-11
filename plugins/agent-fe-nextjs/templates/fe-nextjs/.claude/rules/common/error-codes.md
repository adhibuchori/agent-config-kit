---
paths:
  - 'src/lib/errors/**'
  - 'src/lib/auth/auth-error.ts'
  - 'src/hooks/**'
  - 'src/modules/**'
  - 'src/middlewares/**'
  - 'scripts/check/error-*.ts'
  - 'scripts/check/openapi.ts'
  - 'openapi.json'
---

# Error codes

Applies to a TypeScript API and to the frontends that call it. A code the frontend has no row for
reaches people as "Something went wrong", which is the failure this rule exists to prevent. The API
section binds the backend; the frontend section binds every app that reads its `openapi.json`.

## API

- Every code lives in `src/lib/errors/error-codes.ts` (`ERROR_CODES`). `DomainError` takes an
  `ErrorCode`, so an unlisted code fails `tsc`; the auth library's own error codes use
  `satisfies ErrorCode`. A thrown error always carries a code; never drop to a bare status.
- A new code: add it to the list, throw it, regenerate the OpenAPI spec (`spec:export`), and copy
  `openapi.json` to every frontend that reads it. `error-codes.test.ts` fails on a listed code
  nothing raises.
- `problem.ts` owns the RFC 9457 envelope: `requestId` goes in every body and every error log line,
  5xx go to the error tracker where one is configured, 422 carries `fields` (Zod issue code by path,
  never the value). `detail`, when present, is a client-safe sentence, never an internal message.
- Every problem's `type` is `PROBLEM_TYPE_BASE` plus its code. The base is one absolute https URI
  per API, ending in `/`, with no query or fragment (`https://api.example.com/problems/`), exported
  by `problem.ts` (and handed to the payload middleware as `problemTypeBase` where that contract is
  adopted). The kit's placeholder is `https://example.invalid/problems/`: set yours before the first
  release, refuse to start in production while its host ends in `.invalid`, and never change it
  afterwards, because every installed client resolves failures by it. `title` is fixed per code,
  never per occurrence.
- Never `about:blank`: a 404, a 405, an `HTTPException` and an unknown 500 each map to a registered
  code. A relayed upstream refusal keeps its own code and status, and is minted again under this
  API's base, so its code is in `ERROR_CODES` too.
- The spec publishes the contract on `components.schemas.Problem`: `code` with the `ERROR_CODES`
  enum inline (frontends read it there and follow no `$ref`), `type` with `format: uri` and
  `x-problem-type-base`, both `required`, and no `type` values enumerated. `check:openapi` fails on
  a missing schema, a `$ref` or empty code enum, a code that is not upper snake case, a missing or
  malformed base, or `about:blank` as a default, const or enum value.

## Frontend

- Map every code the app can receive in `src/lib/errors/problem-key.ts`, with copy in every locale
  file. A code the app never receives is listed in `scripts/check/error-codes.ts` with the reason.
  `check:error-codes` fails on anything else, and on a mapped code the API does not send.
- Resolve a problem by its `type`. `problem-key.ts` exports `PROBLEM_TYPE_BASE`, equal to the spec's
  `x-problem-type-base` (`check:error-codes` compares them), and one function reads a body in this
  order: a `type` that is not a string counts as absent; `type` equal to the base plus a known
  `code` gets that code's message; an absent or `about:blank` type falls back to the code alone,
  for an API that does not mint types yet (remove the fallback once it does); anything else, such
  as a known code under another base or a `type` whose last segment is not the `code`, is unknown.
- Branch on the code, never on a bare status when a code exists: "any 400 means duplicate" is how
  a refused request gets reported to people as a success.
- Resolve failures through the app's one error-message helper; a fixed "save failed" line is a
  fallback for `unknown` only. A non-recoverable failure shows its `CODE · <request-id prefix>`
  reference. Never render the backend's `detail`.
- A bare `catch {}` in hooks or components opens with `/* error ignored: <why> */`;
  `check:error-catch` fails on any other. A mutation with no `onError` fails silently: give it one.
- Trace state kept in React holds primitives, not a fresh object per call: an effect that raises
  the same failure otherwise re-renders itself forever.
