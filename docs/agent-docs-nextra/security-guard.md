# security-guard

Agent · agent-docs-nextra · `agent-docs-nextra:security-guard` subagent · reads and reports only · no network

## What it does

`agent-docs-nextra:security-guard` reviews a Nextra docs-site change for response headers and CSP,
secrets reaching the static export, raw HTML and XSS, and the Worker's public addresses.

## When to reach for it

When a change touches `next.config.mjs`, components, `public/`, `wrangler.jsonc` or environment
variables:

```text
Use the agent-docs-nextra:security-guard subagent on this diff.
```

**Not for:** an app or API repo; use [agent-core:security-guard](../agent-core/security-guard.md)
instead.

## Common questions

**Why worry about secrets in a docs site?**
Anything the build reads can end up in the static export that everyone downloads.

## It's working if

- Findings name the header, variable or component and the fix.
- A clean change gets `Security posture unchanged. No new vulnerabilities detected.`

## Where it fits

Used by [/agent-core:review](../agent-core/review.md) in a docs repo.
