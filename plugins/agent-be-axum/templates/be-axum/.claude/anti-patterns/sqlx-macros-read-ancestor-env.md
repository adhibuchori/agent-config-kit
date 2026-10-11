# sqlx's macros read `.env` files from every parent folder at compile time

**Applies to:** `query!`, `query_as!` and friends, sqlx 0.9
**Status:** A standing trap; `.cargo/config.toml` sets `SQLX_OFFLINE = "true"`, and
`cargo-policy.sh` keeps it there

## Symptom

`cargo check` connects to a database nobody named: a `.env` in your home folder or a parent
workspace points `DATABASE_URL` at a shared or production server, and every build describes its
queries there. Builds differ between machines, and a build opens a connection with real
credentials.

## Root Cause

The macros look for `.env` in the crate folder and each of its ancestors, and a parent's value
overrides the crate's (sqlx-macros-core 0.9.0 `query/metadata.rs`). The agent's `.env` guards do
not apply: the compiler reads the file, not a tool call.

## Fix

Keep `[env] SQLX_OFFLINE = "true"` in `.cargo/config.toml`: every build then reads the committed
`.sqlx/` cache. `cargo sqlx prepare` sets its own value and still talks to the database you name.
Never export `SQLX_OFFLINE` in a shell or CI step: an environment value wins over `[env]`.

## When to revisit

If sqlx stops reading ancestor `.env` files, the setting still keeps builds offline.
