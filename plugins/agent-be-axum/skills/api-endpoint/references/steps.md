# Paths and commands per step

| Step | Where | Command |
| --- | --- | --- |
| Register the path | `src/routes/paths.rs` (the constant), `src/routes/<domain>.rs` (the `#[utoipa::path]` handler and its `routes()`), `src/routes/mod.rs` (merge a new domain's `routes()`) | `cargo clippy --locked --all-targets` |
| Red, Green | `tests/api/` for the request test through `app(state).oneshot(...)`; `src/<domain>/service.rs` and `repo.rs` for the code; `src/platform/error.rs` for a new `ErrorCode` | `cargo nextest run --locked` |
| Contract | `openapi.json` (generated; never edited by hand) | `cargo run --locked --quiet --bin openapi` |
| Gates | | `bash scripts/check/gates.sh` |

A request body is read through `ValidJson<T>`, with `#[serde(deny_unknown_fields)]` on `T`, and the
operation declares a 422. The first route that reads a body makes the `expect(dead_code)` attribute
on `mod extract;` in `src/platform/mod.rs` unfulfilled: delete that attribute.

`tests/api/openapi.rs` fails while `openapi.json` is stale, while a response has no description,
while an error response is not `application/problem+json`, and while an operation with a body has
no 422.
