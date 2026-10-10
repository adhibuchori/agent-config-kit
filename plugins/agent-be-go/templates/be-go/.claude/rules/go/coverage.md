---
paths:
  - '**/*.go'
  - 'scripts/check/coverage*'
  - 'scripts/check/gates.list'
  - '.githooks/**'
---

# COVER — Test Coverage (Go)

Every hand-written Go file holds 100% of its statements, measured file by file. Go measures
statements only: there is no branch or function metric, and a package with no test is reported at
0%. Pre-commit runs `scripts/check/coverage-policy.mjs` and then the suite with coverage
(`scripts/check/coverage.sh` through `ci-env.sh`); the quality gate runs both again and reads the
filtered profile for its floor.

## What is measured

`go test -race -count=1 -covermode=atomic -coverprofile=coverage/raw.out ./...`, each package by
its own tests (no `-coverpkg`), never from the test cache: the database may have changed. `coverage-per-file.mjs filter-go` then drops what is exempt, and
`coverage-per-file.mjs check` fails on any remaining file under 100%.

## Exempt, and only these

- Generated code, by its header (`// Code generated ... DO NOT EDIT.`): oapi-codegen's and sqlc's
  output. No line in the list is needed.
- Composition roots, `cmd/*/main.go`: wiring only. A branch that decides something moves into a
  package with a test.

Go has no annotation to skip a block, and this repo adds none: `scripts/check/coverage-exempt.txt`
is the one list, a glob per line with its reason after `#`. A file is never exempt because it is
hard to test; it gets a test, or a seam so it can have one (a constructor that takes what it would
otherwise build, as `postgres.NewPool` takes its config).

## Writing the tests

1. Assert behaviour, never lines: break the line a test guards, watch it fail, restore it.
2. A branch for an error that cannot happen with real inputs (an encoder writing to a closed
   connection) is reached with a writer or a value that fails, not deleted.
3. Tests pin every variable they read: `config.Load` takes a map, never the process environment.
4. A clock or a timeout is passed in, never read from the wall clock.

## Changing the gate

Lowering the threshold, adding an exemption outside the categories above, or running the suite
without `-race` means changing this file, `coverage-exempt.txt` and `scripts/check/coverage.sh`
together, in one change.
