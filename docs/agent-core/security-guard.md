# security-guard

Agent · agent-core · `agent-core:security-guard` subagent · reads and reports only · no network, except the package manager's audit of a new dependency

## What it does

`agent-core:security-guard` reviews a diff for security regressions in any stack: secrets and env
exposure, injection and unsafe sinks, missing authorisation, request trust, dependency advisories,
and edits to the agent's own guardrails (settings, hook config, unlock and `.env` helpers,
workflows). It changes nothing and never opens a `.env*` file.

## When to reach for it

Before you commit a change to config, handlers, queries, rendering of user content or CI:

```text
Use the agent-core:security-guard subagent on this branch.
```

`/agent-core:review` runs it first.

**Not for:** a static site or a docs site; use
[agent-fe-nextjs-static:security-guard](../agent-fe-nextjs-static/security-guard.md) or
[agent-docs-nextra:security-guard](../agent-docs-nextra/security-guard.md) instead.

## Common questions

**Why flag edits to the guardrails?**
A change to `.claude/settings.json`, the unlock script or a workflow changes what the agent may do. A person should read it.

## It's working if

- Each finding names the file, the line and the class of problem.
- A clean diff gets exactly `✓ Security posture unchanged. No new vulnerabilities detected.`

## Where it fits

The security pass of [/agent-core:review](review.md). Static sites and docs sites have their own security guards.
