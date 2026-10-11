---
paths:
  - 'internal/apperr/**'
  - 'internal/httpapi/**'
  - 'internal/**/*codes.go'
  - 'api/openapi.yaml'
---

# Error codes (Go API)

A client keys its message on the code; a code it has no row for reaches people as "Something went
wrong", which is the failure this rule exists to prevent. The web and iOS clients read the code
list from `api/openapi.json`.

## The registry (Rules 6 and 9)

- Every code is a variable in `internal/apperr/codes.go` (or another `*codes.go` there):
  `NotFound = Code{"NOT_FOUND", http.StatusNotFound, "No such route"}`. `Code`'s fields are
  unexported, so no other package can make one up; `registry_test.go` fails on a `Code{}` literal
  outside the package, on a code nothing raises, and on a name that is not UPPER_SNAKE, and the
  `reassign` linter refuses `apperr.NotFound = ...` from outside.
- A new code: add the variable and its line in `Registered()`, add the name to `Problem.code`'s
  enum in `api/openapi.yaml`, raise it, regenerate (`bash scripts/check/generated.sh --write`).
  `contract_test.go` fails while the spec's list and the registry differ.
- A refusal relayed from an upstream service keeps its code and status: `apperr.Lookup(code)` finds
  the registered code of that name, so a relayed code is registered here too. An unknown code is
  this service's INTERNAL.

## The response (Rules 7 and 8)

- Return the error; the router hands it to `apperr.Write`, the only writer of error bodies
  (forbidigo refuses `http.Error`). The body is RFC 9457, `application/problem+json`:
  `{type, title, status, code, detail?, requestId, fields?}`.
- `type` is `apperr.TypeBase` + the code. Set the base once, to an https URI under a domain the
  team owns, unique to this API and ending in `/`, in both `apperr.TypeBase` and
  `x-problem-type-base` in the spec, before the first release; it never changes after, because
  clients key on it. `main` refuses to start in production (`APP_ENV=production`) while it is the
  `example.invalid` placeholder. No problem is `about:blank`: a 404, a 405 and a panic carry codes
  too.
- A code has one status, with one exception: `ENVELOPE_MALFORMED` (the payload contract) is a 400
  for a caller's envelope and a 500 when this service cannot seal its own answer, written with
  `.WithStatus(http.StatusInternalServerError)`.
- `title` belongs to the code, the same every time. `detail` is optional and safe to show a
  client; what only the logs may see goes in `.WithInternal(...)` or the wrapped cause. A 5xx
  never carries a detail.
- `fields` lists `{pointer, code}` per invalid field: a JSON pointer into the body, or
  `/<in>/<name>` for a parameter, and the schema rule it broke. Never the value.
- `requestId` equals the `X-Request-Id` header and appears in the error's log line.
- Every operation in the spec declares `500`; one that takes a body or parameters also declares
  `400`, `413` and `422`; each error response is a `Problem` (`spec_test.go`).
