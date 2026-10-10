---
paths:
  - '**/*.go'
  - 'go.mod'
---

# Dead code (Go)

Blocking in pre-commit and the Quality Gate, where the stack's gates run golangci-lint and
`go mod tidy -diff`.

- golangci-lint's `unused` reports unexported functions, types, fields, constants and variables
  nothing uses; the compiler already refuses an unused import or local variable. `go mod tidy -diff`
  fails when `go.mod` or `go.sum` lists a module nothing imports, or misses one the code does.
- A finding is fixed, not silenced. Unused anywhere: delete it. Reached in a way the linter cannot
  follow (`//go:linkname`, a name looked up by reflection): keep it with
  `//nolint:unused // <who calls it>` on that line.
- Never keep a function, a field or a module requirement because it "might be used later".
- Run `go mod tidy` after adding or removing an import of another module, and commit `go.mod` and
  `go.sum` together.
