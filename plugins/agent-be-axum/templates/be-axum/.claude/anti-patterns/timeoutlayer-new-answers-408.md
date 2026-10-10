# `TimeoutLayer::new` answers 408, and it is deprecated

**Applies to:** tower-http 0.6.7 and later, including 0.7
**Status:** A standing trap; clippy's `disallowed-methods` (clippy.toml) refuses the call

## Symptom

A slow request answers `408 Request Timeout`, which tells the client that it was too slow to send
its request. Clients and proxies may retry a 408 at once, multiplying the load that made the
service slow.

## Root Cause

`TimeoutLayer::new` is `#[deprecated(since = "0.6.7")]` and answers 408 (tower-http 0.7.1
`timeout/service.rs`). Under `build.warnings = "deny"` the deprecation fails the build, which is
how most people meet it.

## Fix

`TimeoutLayer::with_status_code(StatusCode::GATEWAY_TIMEOUT, timeout)`, as in
`src/platform/middleware.rs`; the problem layer then maps the 504 to `REQUEST_TIMEOUT`.

## When to revisit

If tower-http removes `TimeoutLayer::new`, drop it from `disallowed-methods`.
