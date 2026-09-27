# launch-checklist

Command · agent-fe-nextjs-static · `/agent-fe-nextjs-static:launch-checklist [https://live-origin]` · reads and reports · uses the network only for the live origin you give, and asks first

## What it does

`/agent-fe-nextjs-static:launch-checklist` runs every gate and build check, then checks legal pages,
icons, the 404 page, forms, analytics consent and preview indexing, and, given the live URL, its
headers, robots, sitemap and share image. It prints a PASS / FAIL / MANUAL table.

## When to reach for it

Before the first launch, and before any release that changes routes, headers, forms or analytics:

```text
/agent-fe-nextjs-static:launch-checklist https://www.example.com
```

**Not for:** reviewing one change before a commit; use [/agent-fe-nextjs-static:review](review.md)
instead.

## Prerequisites

- node, the repo's gates (`scripts/check/gates.list`) and its `build` script, for a fresh
  production build.
- `pa11y-ci` or `@axe-core/cli`, and `lighthouserc.json` for Lighthouse; a missing tool is marked
  `MANUAL`.
- With a live URL: `curl` and network access to that site.

## Common questions

**Why MANUAL and not PASS?**
A check whose tool is not installed, or a judgement only the owner can make (legal text), is never marked as passed.

## It's working if

- Every row is PASS or an explained MANUAL, with no FAIL.

## Where it fits

The last step for [agent-fe-nextjs-static](../../plugins/agent-fe-nextjs-static/README.md) before going live.
