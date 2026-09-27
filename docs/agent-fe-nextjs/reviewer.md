# reviewer

Agent · agent-fe-nextjs · `agent-fe-nextjs:reviewer` subagent · reads and reports only · no network

## What it does

`agent-fe-nextjs:reviewer` checks a changed TypeScript/TSX diff against your `AGENTS.md`: layer
ownership, logic-free components, styling, data-layer boundaries, the React Compiler, file length,
structure rules and JSDoc.

## When to reach for it

`/agent-core:review` hands it the diff when this plugin is installed. Or ask directly after
editing components, hooks or lib code:

```text
Use the agent-fe-nextjs:reviewer subagent on the staged changes.
```

**Not for:** translation keys, security or SEO; use [i18n-guard](i18n-guard.md),
[agent-core:security-guard](../agent-core/security-guard.md) or [seo-validator](seo-validator.md)
instead.

## Prerequisites

- bun, for the file-length count (`bun run fl`).

## Common questions

**Does it duplicate the linter?**
No. It reviews what no gate checks; formatting and types are the gates' job.

## It's working if

- Each finding cites an `AGENTS.md` rule number.
- A clean diff gets exactly `✓ No violations of the AGENTS.md rules this reviewer checks.`

## Where it fits

Called by [/agent-core:review](../agent-core/review.md).
