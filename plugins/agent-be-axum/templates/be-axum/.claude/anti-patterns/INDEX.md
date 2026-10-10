# Anti-Patterns Index

> Lazy-loaded knowledge base. Load only the file(s) matching your current task.
> Each file is self-contained: symptom, root cause, fix and scope.

## Loading Guide

| Trigger / Task | Load |
| --- | --- |
| A handler that reads a JSON body, or a 422 that quotes what the client sent | axum-json-rejection-echoes-input.md |
| A new request type, or a client field that seems to vanish | serde-accepts-unknown-fields.md |
| Touching the timeout layer, or a 408 from the service | timeoutlayer-new-answers-408.md |
| Touching the request-id layers, or odd request ids in the logs | request-id-trusts-client.md |
| Adding a route, or an endpoint the generated client lacks | utoipa-route-bypasses-spec.md |
| A build that connects to a database, or a `.env` outside this repo | sqlx-macros-read-ancestor-env.md |
| Adding a migration, rebasing a branch that holds one | sqlx-applies-older-migration-silently.md |
| Pool or query options, PgBouncer, wrong rows under load | sqlx-persistent-false-behind-pooler.md |
| Switching a lint off for a module or a file | inner-allow-escapes-allow-attributes.md |
| Touching `[profile.release]`, or a process that restarts on one bad request | panic-abort-kills-catchpanic.md |

### PostgreSQL (shared with agent-be-go)

| Trigger / Task | Load |
| --- | --- |
| Retrying a failed `CREATE INDEX CONCURRENTLY` | cic-retry-keeps-invalid-index.md |
| `CREATE INDEX CONCURRENTLY` in a migration | cic-inside-transaction.md |
| `SET`, `LISTEN` or an advisory lock with a transaction pooler | session-state-behind-transaction-pooler.md |
| Database timeouts in connection options, behind PgBouncer | pgbouncer-rejects-startup-parameters.md |
| `cached plan must not change result type` after a schema change | cached-plan-after-schema-change.md |
| `ALTER DEFAULT PRIVILEGES`, or the app role denied on a new table | default-privileges-without-for-role.md |
| A read-only database role for an agent or a report | read-only-default-is-not-a-boundary.md |
| `ALTER TYPE ... ADD VALUE` in a migration | enum-value-used-in-same-transaction.md |
| DDL on a table the service reads | ddl-without-lock-timeout.md |
| Adding a foreign key | unindexed-foreign-keys.md |

## When to add a new entry

A new anti-pattern qualifies when:

- It cost real debugging time (more than 30 minutes)
- The root cause is not obvious from reading the code or the docs
- The same trap is likely to recur (a vendor behaviour, an environment quirk, a tooling gotcha)

If the cause is fixed upstream, delete the file: a stale entry teaches the wrong thing.

## File naming convention

`<scope>-<short-description>.md`: kebab-case, descriptive enough to skip without opening.
