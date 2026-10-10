// The generator lines: the server code and the contract clients generate from both come from
// api/openapi.yaml. `go generate ./...` writes api.gen.go, then api/openapi.json from the spec
// embedded in it; scripts/check/generated.sh runs the same generators and fails when a committed
// output differs.

package httpapi

//go:generate go tool oapi-codegen -config ../../api/oapi-codegen.yaml ../../api/openapi.yaml
//go:generate go run ../../cmd/openapi ../../api/openapi.json
