# `.persistent(false)` behind a transaction pooler returns another client's rows

**Applies to:** sqlx 0.9 behind PgBouncer in transaction mode
**Status:** A standing trap; the pooler tier (`tests/pooler/`) catches it in CI

## Symptom

Under load, a query returns a row or a number that belongs to another request, with no error.
Reproduced with PgBouncer 1.26.0: 801 of 1,000 answers wrong with `max_prepared_statements = 0`,
770 wrong with 200.

## Root Cause

sqlx prepares with Parse, Describe and Sync, then binds and executes in a second round trip; with
`.persistent(false)` it uses the unnamed statement. A transaction pooler may hand the second round
trip to a server connection where another client's unnamed statement now sits. The sqlx docs
suggest `.persistent(false)` for poolers, which is the unsafe choice here.

## Fix

Leave statements persistent (the default) and run PgBouncer 1.21 or newer with
`max_prepared_statements` above 0 (the default since 1.24), or use session pooling or a direct
connection. Send `extra_float_digits(None)` (`src/platform/db.rs`): PgBouncer refuses that startup
parameter by default.

## When to revisit

When the pooler in front of production changes, run the pooler tier against its settings.
