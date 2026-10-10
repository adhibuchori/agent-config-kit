// Command openapi writes the contract clients generate from (api/openapi.json) from the spec the
// server embeds. `go generate ./...` runs it right after oapi-codegen.
package main

import (
	"fmt"
	"os"

	"example.com/service/internal/httpapi"
)

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: openapi <path to openapi.json>")
		os.Exit(2)
	}
	raw, err := httpapi.GetSpecJSON()
	if err == nil {
		raw, err = httpapi.IndentSpec(raw)
	}
	if err == nil {
		err = os.WriteFile(os.Args[1], raw, 0o644) //nolint:gosec // G306: a committed contract every client reads.
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "openapi:", err)
		os.Exit(1)
	}
}
