# ServeMux answers 404 and 405 in plain text

**Applies to:** `internal/httpapi`, and any router built on `net/http.ServeMux`.
**Status:** a standing trap of the standard library (Go 1.22 to 1.27); kept so the fallback in
`internal/httpapi/fallback.go` is not removed as dead weight.

## Symptom

Clients get `404 page not found` or `Method Not Allowed` as `text/plain` for a wrong path or
method. The web or iOS client's error decoder fails on the body, or shows a generic message with
no code and no request ID, and the log line has no `code` either.

## Root cause

`ServeMux` writes its own answers when no pattern matches: `404` with a plain-text body, and since
Go 1.22's method patterns, `405` with an `Allow` header and a plain-text body. They never reach the
service's error writer, so the RFC 9457 contract (every error has a code) breaks at the edge. A
catch-all `"/"` route would catch the 404 but turn every 405 into a 404, because `"/"` matches any
method.

## Fix

Ask the mux before it answers (`mux.Handler(r)` returns an empty pattern for both cases), run its
fallback against a probe to learn which one it is, and write the problem instead:
`problemFallback` in `internal/httpapi/fallback.go` answers `NOT_FOUND` and
`METHOD_NOT_ALLOWED` (keeping `Allow`). `router_test.go` sends a wrong path and a wrong method
through the real chain and asserts both problems.

## When to revisit

If `net/http` lets a mux take a not-found and a method-not-allowed handler.
