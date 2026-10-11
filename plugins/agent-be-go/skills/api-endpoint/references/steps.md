# Paths and commands per step

| Step | Where | Command |
| --- | --- | --- |
| Seam | `internal/httpapi/*_test.go` through `httpapi.NewRouter` | none yet |
| Contract | `api/openapi.yaml`; a new error code also in `internal/apperr/codes.go` | `go test ./internal/apperr/ ./internal/httpapi/` |
| Generate | `internal/httpapi/api.gen.go`, `api/openapi.json` (both generated) | `bash scripts/check/generated.sh --write` |
| Red, Green | `internal/httpapi/handlers.go` (one method on `Handlers`), `internal/<module>/` | `go test ./internal/...` |
| Gates | | `bash scripts/check/gates.sh` |

- A request body is an object schema with `additionalProperties: false`; the validator refuses
  unknown and wrong-case keys before the generated code decodes.
- An operation with a body or parameters declares `400`, `413` and `422`; every operation declares
  `500`; each is the `Problem` response (`internal/httpapi/spec_test.go` checks).
- A new error code: its variable in `internal/apperr/codes.go` and `Registered()`, its name in
  `Problem.code`'s enum, raised by the service (`registry_test.go` and `contract_test.go` check).
- The service the handler calls is a field of `Handlers`, built in `cmd/api/main.go`.
