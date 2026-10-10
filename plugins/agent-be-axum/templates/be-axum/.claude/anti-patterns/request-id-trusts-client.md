# `SetRequestIdLayer` keeps whatever `x-request-id` the client sent

**Applies to:** tower-http's request-id layers
**Status:** A standing trap; `drop_untrusted_request_id` in `src/platform/middleware.rs` is the fix

## Symptom

Log lines carry request ids such as a 10 KB string, a line break that forges a second log entry,
or the same id on thousands of unrelated requests, because a client chose it. The id a support
ticket quotes no longer identifies one request.

## Root Cause

`SetRequestIdLayer` generates an id only when the header is absent; an existing header wins
(tower-http 0.7.1 `request_id.rs`, `call()`).

## Fix

Before `SetRequestIdLayer`, drop a client value that is not a plain token (1 to 64 letters,
digits, `-`, `_`, `.`), so a fresh id replaces it. Keep a valid one: a caller that sends its own
id can follow its request through your logs.

## When to revisit

If the service sits behind a proxy that sets the id itself, trust only that proxy's header and
drop the client's.
