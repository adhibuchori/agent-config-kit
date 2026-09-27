# skeleton

Skill · agent-fe-nextjs · `agent-fe-nextjs:skeleton` · edits skeleton components, measures them · no network

## What it does

The `skeleton` skill builds, fixes or checks a loading skeleton so it matches the screen it stands
in for. It derives heights from the real component, wires the preview switch, and measures the pair
at four widths until they differ by at most half a pixel.

## When to reach for it

Claude loads it when you mention a skeleton, a loading state, a placeholder or layout shift:

```text
The dashboard skeleton jumps when the data arrives. Fix it.
```

**Not for:** a layout bug outside a loading placeholder; use [/agent-core:rca](../agent-core/rca.md)
instead.

## Prerequisites

- The files [/agent-fe-nextjs:setup](setup.md) installs when you answer yes to its `skeletons`
  question; without `.claude/rules/web/skeletons.md` it says so and stops.
- A way to measure: the repo's `bun run measure:skeletons` harness, or a running dev server with
  Playwright or the DevTools protocol.

## Common questions

**It says the rules are missing.**
Answer `yes` to the `skeletons` question: run `/agent-fe-nextjs:setup` (or `/agent-fe-nextjs:sync` after changing the answer).

## It's working if

- The report has a table of heights measured at 375, 768, 1024 and 1440 px wide, with the skeleton
  and the real screen within 0.5 px at each.
- `git diff` shows `IS_SKELETON_SHOWN` back to `false` before you commit.

## Where it fits

Optional module of [agent-fe-nextjs](../../plugins/agent-fe-nextjs/README.md).
