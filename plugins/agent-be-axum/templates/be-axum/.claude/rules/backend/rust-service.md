---
paths:
  - 'src/**/*.rs'
  - 'Cargo.toml'
  - 'clippy.toml'
  - 'rustfmt.toml'
  - 'rust-toolchain.toml'
  - 'deny.toml'
  - '.cargo/**'
---

# Rust + Axum service

How the rules in `AGENTS.md` look in this crate. The gates (`bash scripts/check/gates.sh`) check
what can be checked; the rest is on you and the reviewer.

## Layout (Rules 1 to 5, 10)

```text
src/main.rs              runtime, startup checks, serve with a shutdown deadline (wiring only)
src/lib.rs               composes: app(state) and openapi(); nothing else
src/platform/            config.rs (the one env reader), db.rs (the pool), error.rs (codes and
                         problem()), extract.rs (ValidJson), middleware.rs (layers), state.rs
src/routes/              paths.rs (every path), mod.rs (merges one routes() per domain),
                         <domain>.rs (handlers with #[utoipa::path])
src/<domain>/            mod.rs (the domain's surface), service.rs, repo.rs (private), model.rs
src/bin/openapi.rs       prints the spec into openapi.json
```

- A request goes handler → service → repo. The handler extracts, calls one service function and
  shapes the response in 15 lines or fewer. The service holds the rules and names no HTTP type.
  The repo holds the SQL, and `mod repo;` stays private, so a handler cannot reach it.
- A domain's `mod.rs` re-exports the few items others use; everything else is `pub(crate)` or
  private. `pub` appears only on what `lib.rs` re-exports (`unreachable_pub` holds this).
- A trait arrives with its second implementation. One implementation plus a test fake of your own
  code is a seam you do not need yet; a fake for a real external system (a payment API) counts.
- A new route: a const in `routes/paths.rs`, a handler with `#[utoipa::path(path = paths::X, ...)]`,
  and `routes!(handler)` in that domain's `routes()`. A route added with `.route(` serves requests
  but never reaches `openapi.json`, so `rust-source.mjs` refuses it outside `routes/mod.rs`.
- Modules use `mod.rs`, never `name.rs` beside `name/`, so a folder holds files or folders.

## Runtime (Rules 18 to 21)

- The layers in `platform/middleware.rs` run outermost first: a client's `x-request-id` is kept
  only when it is a plain token, then set, traced and propagated; bare error statuses become
  problem bodies; panics answer 500; CORS lists its origins; the body limit answers 413; the
  timeout answers 504 (`TimeoutLayer::with_status_code`, never `TimeoutLayer::new`, which answers 408).
- Configuration comes from `Config`, read once at startup. A new setting is a field there, with a
  default or a `Missing` error, and a test.
- Log with `tracing` and structured fields. A 5xx is logged once, in `AppError::into_response`.
- Outside tests, return errors with `?`. A value that cannot be absent is a type that cannot be
  absent; a lookup that can fail returns `Option` and the caller decides.

## Code quality (Rules 22 to 24, 27 to 29)

- A file holds at most 200 lines of code. Split by what the code does, never into `utils.rs`.
- A suppression names its lint and its reason: `#[expect(clippy::too_many_lines, reason = "...")]`.
  It fails the build once the lint stops firing, so it never outlives its cause.
- Convert numbers with `From` and `TryFrom`. A `serde_json::Value` is parsed into a struct with
  `#[serde(deny_unknown_fields)]` where it enters, and request bodies arrive through `ValidJson`.
- `Cargo.lock` is committed and every cargo command passes `--locked`. An upgrade moves one crate
  family (axum with axum-core and utoipa-axum, say) in its own pull request, after reading the
  CHANGELOG between the two versions: a 0.x patch release has changed behaviour before.
- The release profile keeps `panic = "unwind"` and `overflow-checks = true`; `cargo-policy.sh`
  checks both, with the rest of `.cargo/config.toml`.
- Secrets live in the environment of the running service, never in `.env` files the compiler can
  read: sqlx's macros read `.env` from every parent folder, and `SQLX_OFFLINE = "true"` keeps them
  on the committed `.sqlx/` instead.
