# A closed OpenAPI enum turns a new error code into a decoding failure

**Applies to:** the generated client and `Problem.code` (AGENTS.md Rule 12)
**Status:** Permanent (swift-openapi-generator's documented default)

## Symptom

The backend ships a new error code. Installed apps stop showing any message for that call: the
request throws a decoding error instead of returning a problem, so the screen shows a generic
failure without the code or the request id, and support cannot trace it.

## Root cause

swift-openapi-generator turns a string `enum` into a closed Swift enum; "decoding fails if an
unknown value is encountered" (Useful OpenAPI patterns, 1.14.0). An installed app cannot be updated
together with its backend, so every code added after the build shipped breaks every response that
carries it. Reproduced with a canned transport: the call threw, and the mapping code never ran.

## Fix

The client decodes every `Problem` into the hand-written `AppProblem` through `typeOverrides` in
`Packages/AppCore/Sources/APIClient/openapi-generator-config.yaml`. `AppProblem` reads `code` as a `String`
and resolves it with `knownCode`; an unknown code becomes the generic message plus the reference
`CODE · requestId`. The spec keeps its inline enum, which `scripts/check/error-codes.sh` compares
with `ProblemCode`.

## How to catch it

`error-codes.sh` fails when the spec lists a code `ProblemCode` lacks. A test of `AppProblem`
decodes a body with a code the app does not know.

## Scope

Every enum in a response the backend may extend. Open it the same way, or with the generator's
`anyOf` pattern (a string schema beside the enum).
