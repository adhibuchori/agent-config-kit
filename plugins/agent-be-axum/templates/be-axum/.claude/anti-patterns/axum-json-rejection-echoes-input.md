# axum's `Json` rejection quotes the value the client sent

**Applies to:** axum 0.8 handlers that take `axum::Json<T>` as their body
**Status:** A standing trap; `ValidJson<T>` (`src/platform/extract.rs`) is the fix in this repo

## Symptom

A 422 body reads `Failed to deserialize the JSON body into the target type: name: invalid type:
string "secret-value-123", expected u32 at line 1 column 27`. The submitted value, a password or
a card number in the worst case, comes back to the client and into every log that records
response bodies. It is plain text, not a problem body, and has no code.

## Root Cause

axum-core's `JsonDataError` displays its body text followed by the `serde_path_to_error` message,
which quotes the offending value (axum-core 0.5.6 `macros.rs`, axum 0.8.9 `json.rs`; reproduced
with a test in the research sample).

## Fix

Read bodies through `ValidJson<T>`: it parses with `serde_path_to_error`, keeps only the path
(`fields: [{ "field": "name", "code": "INVALID" }]`) and answers through `problem()`. A test sends
a wrong value and asserts the value is absent from the body.

## When to revisit

If axum's rejection stops quoting input, `ValidJson` still gives the problem body and the code.
