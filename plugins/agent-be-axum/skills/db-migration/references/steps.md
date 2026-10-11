# Paths and commands per step

| Step | Where | Command |
| --- | --- | --- |
| Expand | `migrations/<version>_<name>.sql`; a concurrent index alone in its own file, whose first line is `-- no-transaction` and second `-- squawk-disable-assume-in-transaction` | `sqlx migrate add <name>` |
| Check | the new file | `bash scripts/check/migrations.sh` |
| Apply, refresh | your local database at `DATABASE_URL`; `.sqlx/` (generated) | `sqlx migrate run`, then `cargo sqlx prepare -- --all-targets` |
| Prove | `tests/db/` with `#[sqlx::test]`, which applies `migrations/` to a fresh database | `bash scripts/check/gates.sh` |

`-- no-transaction` counts only as the file's first bytes: after a space or a blank line it is a
comment. A rebase that puts your version below the newest one on the base branch needs a new
timestamp: CI's `migrations.sh --base` refuses it, because sqlx would apply it out of order.
