# Anti-Patterns Index

> Load only the file that matches your task. Each one is self-contained: symptom, root cause, fix.

## Loading guide

| Trigger / task | Load |
| --- | --- |
| A wrong path or method answered in plain text, or touching `internal/httpapi/fallback.go` | servemux-404-405-skip-problem-json.md |
| Adding a request body, or a client's extra or wrong-case key that was accepted | json-decoder-accepts-unknown-and-case-insensitive-keys.md |
| Adding an error code, or a code the client did not know | closed-error-codes-are-not-closed.md |
| Running behind PgBouncer, or changing `default_query_exec_mode` | pgx-describe-exec-behind-pooler.md |
| Touching the pool size, `DB_MAX_CONNS`, or "too many clients" | pgxpool-size-follows-cpu-count.md |
| Wanting to fix a migration that is already merged | goose-never-detects-edited-migrations.md |
| Linting one file by hand, or a lint result that differs from the gate's | golangci-lint-file-mode-and-fast-only.md |
| Retrying a failed concurrent index build, or an index the planner ignores | cic-retry-keeps-invalid-index.md |
| Building an index concurrently in a migration | cic-inside-transaction.md |
| `SET`, advisory locks or `LISTEN` behind a pooler | session-state-behind-transaction-pooler.md |
| Setting a timeout in a connection string, or `08P01 unsupported startup parameter` | pgbouncer-rejects-startup-parameters.md |
| `cached plan must not change result type` after a deploy | cached-plan-after-schema-change.md |
| Editing `db/roles.sql` or any grant, or `permission denied` right after a migration | default-privileges-without-for-role.md |
| Setting up a read-only role for an agent or a report | read-only-default-is-not-a-boundary.md |
| Adding a value to an enum type | enum-value-used-in-same-transaction.md |
| Any migration that alters an existing table | ddl-without-lock-timeout.md |
| Adding a foreign key | unindexed-foreign-keys.md |

## When to add a new entry

A new anti-pattern qualifies when it cost real debugging time (over 30 minutes), its root cause is
not obvious from the code or the docs, and the same trap is likely to come back (a library quirk,
an environment, a tool). When the trap is fixed upstream, delete its file.

## File naming

`<scope>-<short-description>.md`, kebab-case, clear enough to skip without opening.
