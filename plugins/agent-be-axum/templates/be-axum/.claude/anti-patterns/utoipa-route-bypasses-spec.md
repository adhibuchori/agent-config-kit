# A route added with `.route()` is served but missing from `openapi.json`

**Applies to:** utoipa-axum's `OpenApiRouter`
**Status:** A standing trap; `rust-source.mjs` ROUTES refuses `.route(` outside `src/routes/mod.rs`
and `src/lib.rs`

## Symptom

An endpoint works in production while the generated clients have no method for it, and the spec
drift test passes, because the spec and the code agree on everything the spec lists.

## Root Cause

`OpenApiRouter::route()` is a pass-through to axum's `Router::route`: the method router reaches
axum, the operation never reaches the document (utoipa-axum 0.3.0 `router.rs`). Only
`.routes(routes!(handler))` adds both from one `#[utoipa::path]`.

## Fix

Every route: a const in `src/routes/paths.rs`, a handler with `#[utoipa::path(path = paths::X)]`,
and `routes!(handler)` in its domain's `routes()`. Then regenerate `openapi.json`.

## When to revisit

If utoipa-axum makes `.route()` record operations, the ROUTES check can relax.
