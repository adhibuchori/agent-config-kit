# security-guard

Agent · agent-fe-nextjs-static · `agent-fe-nextjs-static:security-guard` subagent · reads and reports only · no network

## What it does

`agent-fe-nextjs-static:security-guard` reviews a static-site diff for security regressions: response
headers in the host's config (the `_headers` file, not `next.config` under export), a hash-based CSP
that still matches the build, secrets in public variables, XSS sinks and unsafe URLs, form
endpoints, third-party scripts, and edits to the agent's own guard files.

## When to reach for it

Before committing a change to headers, `next.config`, forms, scripts or rendered HTML:

```text
Use the agent-fe-nextjs-static:security-guard subagent on this diff.
```

**Not for:** an app or API repo; use [agent-core:security-guard](../agent-core/security-guard.md)
instead.

## Prerequisites

- node, for `node scripts/check/security-headers.mjs`, and a fresh build when the CSP lists hashes
  (`--verify-hashes`).

## Common questions

**Why does a hash CSP go stale?**
Next.js inlines scripts whose hashes change on every build, so the headers file must be refreshed from the build (`--print-hashes`).

## It's working if

- Header, CSP and form findings are listed with the file and the fix.
- A clean diff gets exactly `✓ Security posture unchanged. No new vulnerabilities detected.`

## Where it fits

Used by [/agent-fe-nextjs-static:review](review.md).
