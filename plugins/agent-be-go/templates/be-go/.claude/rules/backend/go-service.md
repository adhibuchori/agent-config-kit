---
paths:
  - 'cmd/**/*.go'
  - 'internal/**/*.go'
  - 'api/**'
  - 'go.mod'
  - '.golangci.yml'
---

# Go service

How this service is laid out and why. The rule statements are the index in `AGENTS.md`; this file
holds the how. golangci-lint (`.golangci.yml`) and the compiler enforce most of it.

## Layout and layers (Rules 1–4)

| Package | Holds | May import |
| --- | --- | --- |
| `cmd/api` | `main`: config, logger, pool, router, server, shutdown; no logic | everything |
| `internal/config` | the only reader of the environment (`Load(os.LookupEnv)`) | the standard library |
| `internal/apperr` | the code registry and the RFC 9457 writer | `logging` |
| `internal/logging` | the slog setup and the request ID in a context | the standard library |
| `internal/httpapi` | the generated server, the handlers, the middleware | `apperr`, `logging`, `config`, modules |
| `internal/<module>` | one domain: its service, its types, the `Store` interface it consumes | `apperr`, `logging` |
| `internal/payload` | with `payload-encryption`: the payload contract's core, no HTTP (`go-payload.md`) | the standard library |
| `internal/postgres` | the pool, sqlc's queries (`db/`), one store per module | `apperr`, modules' types, pgx |

- A request flows handler → service → store. A module never sees HTTP and never imports pgx; it
  returns an `apperr` error and asks its `Store` for data. depguard holds these lines.
- A module is deep: a few exported functions over much behaviour. Delete it in your head; if the
  callers would barely change, it was a pass-through, so fold it in. `internal/<module>/internal/`
  keeps helpers private to that module. Name packages after what they hold (`billing`, `postgres`).
- An interface lives with its consumer (`billing.Store`, declared in `internal/billing`) and appears
  once a second implementation exists. The hand-written fake that stands in for a real external
  system in tests counts as the second. One implementation is a concrete type.

## Contract first (Rules 5 and 10)

- `api/openapi.yaml` is the contract. `bash scripts/check/generated.sh --write` regenerates
  `internal/httpapi/api.gen.go` (oapi-codegen strict server) and `api/openapi.json`; the build then
  fails until the new operation has its method on `Handlers`. Route paths exist only in generated
  code, so a `"/api/...` literal in hand-written Go fails `scripts/check/endpoints.sh`.
- A handler decodes nothing by hand: the generated code binds the request after the validator has
  checked it against the spec. It calls the service and returns the typed response, or the error.
  Fifteen code lines at most (`internal/httpapi/handler_size_test.go`).
- Request bodies set `additionalProperties: false`: Go's decoder accepts unknown keys and matches
  names without regard to case, and the validator is what refuses them.

## Server and middleware (Rule 18)

- The chain, outermost first: request ID, access log, panic recovery, body limit
  (`http.MaxBytesReader`), spec validation, routes, and the 404/405 fallback. The request ID goes
  in the `X-Request-Id` header, every problem body and every log line of the request.
- `httpapi.NewServer` sets `ReadHeaderTimeout`, `ReadTimeout`, `WriteTimeout` and `IdleTimeout`;
  `main` waits for `Shutdown` to return. A browser client gets CORS from an explicit origin list in
  `internal/config`, never `*`.

## Go house rules (Rules 19–24)

- Only `internal/config` calls `os.Getenv`/`os.LookupEnv`; `main` hands it `os.LookupEnv`.
- Log through the `*slog.Logger` passed in, with `LogAttrs(ctx, ...)`, a static message and
  camelCase keys (`requestId`). No `fmt.Print*`, no `log.*`.
- A context is the first parameter and never a struct field. `main` starts the only root context;
  tests use `t.Context()`.
- 200 code lines per file; a longer file is two concerns. revive counts lines without blank and
  comment lines; it also subtracts a comment at the end of a code line, so do not pad lines with them.
- A suppression is `//nolint:<linter> // <why>` on the line, and only while needed: nolintlint
  fails a bare `//nolint`, a missing reason and a stale one. A rule in `.golangci.yml` carries its
  reason as a comment, and `scripts/check/lint.sh` fails one that excludes nothing.
- Prefer the standard library, then a module already in `go.mod`, then a new one. `go.mod`'s
  `tool` lines pin oapi-codegen, sqlc, goose and govulncheck; run them with `go tool <name>`.
  golangci-lint is the release `scripts/check/tools.env` names.

## Done

`bash scripts/check/gates.sh` passes. It needs golangci-lint, gitleaks, Node 20+ and a PostgreSQL
the tests reach (`.claude/rules/backend/testing.md`).
