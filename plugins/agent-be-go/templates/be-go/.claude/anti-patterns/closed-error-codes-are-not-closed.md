# A "closed" set of error codes that is not closed

**Applies to:** `internal/apperr` and every package that returns an error to a client.
**Status:** a standing trap of Go's type system; kept as the reason `apperr.Code` looks the way it
does.

## Symptom

A client receives a code that is in no list: `"THING_GONE"` where the spec says `NOT_FOUND`. The
web app shows "Something went wrong", the iOS app cannot decode the error at all, and nothing
failed in CI.

## Root cause

The obvious designs accept any string:

- `type Code string` with constants: `apperr.Code("MADE_UP")` compiles anywhere.
- The `ProblemCode` enum oapi-codegen generates from the spec is also `type ProblemCode string`.

A struct with unexported fields (`Code{name, status, title}`) stops other packages from naming a
new code, but two holes remain: the zero literal `apperr.Code{}` compiles everywhere, and an
exported variable can be re-pointed from outside (`apperr.NotFound = apperr.Internal`).

## Fix

All four, as this repo has them:

1. `Code` has unexported fields; the registry is the variables in `internal/apperr/*codes.go`.
2. `registry_test.go` reads every Go file with go/ast and fails on a `Code{...}` literal outside
   `apperr`, on a registered code nothing raises, and on a mismatch with `Registered()`;
   `contract_test.go` fails while the spec's `Problem.code` enum differs from the registry.
3. The `reassign` linter with `patterns: [".*"]` (its default patterns miss this) refuses a
   re-pointed code.
4. `apperr.Write` answers a zero code as `INTERNAL`, so a `var c apperr.Code` that slips through
   still reaches the client as a registered code.

## When to revisit

If Go gains closed enums.
