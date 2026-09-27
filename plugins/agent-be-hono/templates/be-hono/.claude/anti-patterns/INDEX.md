# Anti-Patterns Index

> Lazy-loaded knowledge base. Load only the file(s) matching your current task.
> Each file is self-contained — root cause + fix + scope.

## Loading Guide

| Trigger / Task | Load |
| --- | --- |
| Touching `src/db/client/index.ts` or connection pool config | postgres-max-1-pool.md |
| Touching `src/middlewares/rate-limit.middleware.ts` | rate-limit-double-next.md |
| Writing a `bun test` file that needs a module replaced, or a result that ignores its steering | bun-mock-module-is-process-wide.md |
| Writing or editing any guard under `scripts/check/` or `.github/scripts/` | a-check-that-matches-nothing-passes.md |
| Adding anything to better-auth's `hooks.after`, or reordering its `plugins` | better-auth-user-hook-runs-first.md |
| Ending a session, or changing a column the session snapshot carries (`role`, `banned`, …) | session-rows-are-a-mirror-not-the-session.md |
| Passing `jobId` to a queue, or chasing a job that was never processed | queue-job-id-cannot-contain-colon.md |
| Revoking sessions or banning a user, or a "session expired" flow that bounces back | auth-cookie-cache-outlives-revocation.md |
| Building an account-security flow on the auth client (unlink, list sessions, set a password) | better-auth-account-endpoints-are-gated.md |
| Passkey registration or sign-in, cancellation handling, user verification | better-auth-passkey-quirks.md |
| Passing a list option (paths, origins) to a Better Auth plugin | better-auth-list-option-replaces-defaults.md |
| Cancelling or superseding a payment (or any remote resource) and acting on the result | gateway-cancel-result-is-not-the-state.md |

## When to add a new entry

A new anti-pattern qualifies when:

- It cost real debugging time (>30 min)
- The root cause is non-obvious from reading code/docs
- Same trap is likely to recur (vendor bug, environment quirk, tooling gotcha)

If the bug gets fixed upstream, **delete the file** — don't leave stale entries.

## File naming convention

`<scope>-<short-description>.md` — kebab-case, descriptive enough to skip without opening.
