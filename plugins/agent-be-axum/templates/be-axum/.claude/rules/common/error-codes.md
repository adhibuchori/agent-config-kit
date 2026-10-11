---
paths:
  - 'src/platform/error.rs'
  - 'src/platform/extract.rs'
  - 'src/platform/middleware.rs'
  - 'src/routes/**'
  - 'src/*/service.rs'
  - 'tests/api/**'
  - 'openapi.json'
---

# Error codes (Rules 6 to 9)

A client knows a failure by its code. A code the client has no message for reaches people as
"Something went wrong", which is the failure this rule exists to prevent.

## The contract

- Every code is a variant of `ErrorCode` in `src/platform/error.rs`, `pub(crate)`. `problem()`
  takes a `WireCode`, which `ErrorCode` is, so an unlisted code does not compile, and a variant
  nothing builds fails the build through `dead_code`. A contract with a closed list of its own (the
  payload contract's `PayloadCode`) implements `WireCode` too, and lists its codes in the spec. `ErrorCode` never derives `Deserialize`: the derived parser would
  build every variant and hide the unused ones (`rust-source.mjs` refuses it).
- Every error body comes from `problem()`: `application/problem+json` (RFC 9457) with `type`,
  `title`, `status`, `code`, the request's `requestId`, and on a 422 `fields`: each refused field
  by its path and a `FieldCode`, never the value that was sent.
- `type` is `PROBLEM_TYPE_BASE` followed by the code. Set the base once, to an https URL your team
  owns, before the first release; changing it later breaks every client, installed apps included.
  The service refuses to start in production (`APP_ENV=production`) while the base is still the
  `.invalid` placeholder. `about:blank` is never sent: a missing route or a timeout has a code too.
- `title` is one per code (`ErrorCode::title`) and never carries details of one occurrence. No
  body carries an internal message: the `Display` text of an error goes to the log.

## Adding a code

1. Add the variant, its wire name in `as_str` and its `title`.
2. Return it: an `AppError` variant mapped in `into_response`, or a status the layers map.
3. Declare its status on every operation that can return it, with a `description`, and a 422 on
   every operation that takes a body; `tests/api/openapi.rs` checks the declarations it can see.
4. Regenerate `openapi.json` (`cargo run --locked --quiet --bin openapi`) and copy
   it to every client that reads it, so each maps the new code to a message.

A refusal relayed from a service you call keeps its code and status, minted again under this
API's base, so that code is in this list too.
