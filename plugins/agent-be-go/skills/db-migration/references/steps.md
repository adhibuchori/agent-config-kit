# Paths and commands per step

| Step | Where | Command |
| --- | --- | --- |
| Expand | `db/migrations/<version>_<name>.sql` | `go tool goose -dir db/migrations create <name> sql` |
| Check | the new file | `bash scripts/check/migrations.sh` |
| Apply | the test database (`.claude/rules/backend/testing.md`); `internal/postgres/main_test.go` migrates it before the tests | `bash scripts/check/ci-env.sh bash scripts/check/coverage.sh` |
| Regenerate | `db/queries/*.sql` in, `internal/postgres/db/` out (generated) | `bash scripts/check/generated.sh --write` |
| Prove | `internal/postgres/*_test.go` | `bash scripts/check/gates.sh` |

A file goose runs outside a transaction starts with:

```sql
-- +goose NO TRANSACTION
-- +goose Up
CREATE INDEX CONCURRENTLY things_owner_id_idx ON things (owner_id);
```

A transactional file sets its lock timeout first:

```sql
-- +goose Up
SET LOCAL lock_timeout = '3s';
ALTER TABLE things ADD COLUMN archived_at timestamptz;
```

Write a `-- +goose Down` section only when the change can be undone without losing data; the gate
lints the Up part.
