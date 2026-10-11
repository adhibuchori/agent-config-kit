---
paths:
  - '**/*_test.go'
  - '**/testdata/**'
  - '.env.ci.example'
  - 'scripts/check/coverage.sh'
  - 'scripts/check/pooler.sh'
---

# Testing (Go)

One tier: every test runs with `go test`, against a real PostgreSQL where it needs one, and every
hand-written file reaches 100% of its statements (`.claude/rules/go/coverage.md`).

## The database

- The tests connect as the service's role, `app_rw`, to the database `TEST_DATABASE_URL` names.
  `.env.ci.example` holds it; `scripts/check/ci-env.sh` passes it to the tests and nothing else from
  your shell. `internal/postgres/main_test.go` first applies every migration to that database as the
  migrator (`TEST_MIGRATIONS_URL`), so the tests always run on the branch's schema. The quality gate
  starts PostgreSQL 18 and runs `db/roles.sql`; locally, once per machine:

  ```bash
  docker run -d --name pg-test -p 5432:5432 -e POSTGRES_HOST_AUTH_METHOD=trust postgres:18.6
  psql "postgres://postgres@127.0.0.1:5432/postgres" -v ON_ERROR_STOP=1 -f db/roles.sql
  ```

  A test that needs the database and cannot reach it fails and says so; it never skips.
- A store test hands the store a transaction and rolls it back in `t.Cleanup`, so each test sees
  only its own rows and leaves nothing behind. Stores therefore take what sqlc's `DBTX` and
  `Begin` need, which a pool and a transaction both provide; a store's own transaction then
  becomes a savepoint. A test that needs committed data from another session gets a database of
  its own (`CREATE DATABASE ... TEMPLATE app_test`). Only `internal/postgres` touches the database.
- `internal/postgres/pool_test.go` proves the role: its timeouts are set, and it cannot create a
  table. `pooler_test.go` runs only in the quality gate, behind PgBouncer.

## How a test reads

- Test behaviour through the seam a caller uses: a handler through `httpapi.NewRouter` and a real
  `httptest` request, a service through its exported functions, a store against the database.
  The test survives a rewrite of the inside.
- Expected values come from the contract: the status, the code and the field the spec names,
  written as literals. A value recomputed with the code under test proves nothing.
- Replace only a system boundary (another service's API, the clock, a payment provider), with a
  small hand-written fake. Packages of this repo are never replaced; depguard refuses mocking
  libraries.
- Table tests with `t.Run`, `t.Parallel()` where the test shares nothing, `t.Context()` for a
  context, `t.Helper()` in helpers. Errors are compared with `errors.Is` or by code, never by
  message text: Go 1.27's JSON errors read differently from earlier releases.
- A test that guards a line: break the line, watch the test fail, restore the line.

## Signs of a weak test

- It asserts what a fake returned (tautological), or the order of internal calls (coupled to the
  implementation).
- It builds every layer's tests first and the behaviour last (horizontal slices). Write one test
  for one behaviour end to end, make it pass, then the next.
