# A retried `CREATE INDEX CONCURRENTLY IF NOT EXISTS` keeps an INVALID index

**Applies to:** every migration that builds an index concurrently.
**Status:** a standing trap of PostgreSQL itself (reproduced on 18.6, 17.11 and 16.15).

## Symptom

A deploy fails halfway through a concurrent index build (a deadlock, a unique violation, a
timeout, a killed pod). The retry, or the next deploy, runs the same migration with
`IF NOT EXISTS`, prints `NOTICE: relation "..." already exists, skipping`, and succeeds. Queries
stay slow: the planner never uses the index, and `\d` lists it as `INVALID`. Writes still pay to
maintain it.

## Root cause

A failed `CREATE INDEX CONCURRENTLY` does not roll back the way a transactional statement does: it
leaves the index behind, marked invalid (`pg_index.indisvalid = false`). `IF NOT EXISTS` checks the
name only, so it finds the broken index and skips the build. The PostgreSQL docs say to drop the
index and try again, or rebuild it with `REINDEX INDEX CONCURRENTLY`; squawk's own
`prefer-robust-stmts` documentation admits the retry "falsely succeeds".

## Fix

Drop the invalid index, then build it again, each as the only statement of a new migration that
runs outside a transaction (`cic-inside-transaction.md`):

```sql
DROP INDEX CONCURRENTLY IF EXISTS things_owner_id_idx;      -- one file
CREATE INDEX CONCURRENTLY things_owner_id_idx ON things (owner_id); -- the next file
```

Find the leftovers on any database:

```sql
select indexrelid::regclass as index_name, indrelid::regclass as table_name
from pg_index where not indisvalid;
```

The quality gate runs that query on the database it migrates from scratch, so a migration that
cannot build its index fails the pull request rather than production.

## When to revisit

If PostgreSQL ever rolls a failed concurrent build back, or `IF NOT EXISTS` starts checking
validity.
