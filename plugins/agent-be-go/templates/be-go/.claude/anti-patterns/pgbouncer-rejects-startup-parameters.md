# PgBouncer refuses timeouts sent as startup parameters

**Applies to:** a service that sets server timeouts in its connection string or driver options
and may run behind PgBouncer.
**Status:** a standing trap (reproduced with PgBouncer 1.26.0 in its default configuration).

## Symptom

Direct to PostgreSQL everything works. Behind the pooler, every connection fails at once with
`FATAL: unsupported startup parameter: statement_timeout` (SQLSTATE `08P01`), or, through libpq's
`options=-c statement_timeout=...`, with `unsupported startup parameter in options`. With
`ignore_startup_parameters = statement_timeout` the connection opens and the timeout is silently
**not applied**: `current_setting('statement_timeout')` reads `0`.

## Root cause

A driver sends a timeout given in the connection string (a URL parameter, a runtime parameter, an
`options` value, `PGOPTIONS`) in the startup packet. PgBouncer passes on only the parameters it
tracks and, by its docs, raises an error for "all other parameters" unless they are listed in
`ignore_startup_parameters` (then dropped) or `track_extra_parameters`.

## Fix

Set the timeouts on the role the service logs in as, which holds with or without a pooler:

```sql
ALTER ROLE app_rw SET statement_timeout = '10s';
ALTER ROLE app_rw SET idle_in_transaction_session_timeout = '15s';
```

Keep them out of the connection string and the driver's options. A test that connects as the role
and reads `current_setting(...)` proves the values whatever their source.

## When to revisit

If the pooler config adds these names to `track_extra_parameters` and every environment is known
to carry that config.
