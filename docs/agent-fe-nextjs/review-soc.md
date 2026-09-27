# review-soc

Command · agent-fe-nextjs · `/agent-fe-nextjs:review-soc [path]` · runs the gates, then moves code · no network of its own

## What it does

`/agent-fe-nextjs:review-soc` runs the separation-of-concerns gates, then moves what they find out of
components into hooks, `src/lib/` and the constants homes. Every finding names its destination.

## When to reach for it

Before a commit that touches components, or when a screen feels heavy:

```text
/agent-fe-nextjs:review-soc src/app/(dashboard)
```

**Not for:** reviewing a diff against every rule; use [/agent-core:review](../agent-core/review.md)
instead.

## Prerequisites

- bun, and the checks [/agent-fe-nextjs:setup](setup.md) installs: `scripts/check/soc.ts` and the
  `check:*` package scripts. Without `soc.ts` it says so and stops.

## Common questions

**Why run gates instead of reading the diff?**
A category with no command is a category nobody checks. `check:soc` counts findings per category, which becomes the worklist.

## It's working if

- `bun run check:soc` ends with zero findings, or only allowed ones.

## Where it fits

Part of [agent-fe-nextjs](../../plugins/agent-fe-nextjs/README.md), next to [reviewer](reviewer.md).
