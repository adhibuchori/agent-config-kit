# a11y-audit

Command · agent-fe-nextjs · `/agent-fe-nextjs:a11y-audit [path]` · reads and reports · no network

## What it does

`/agent-fe-nextjs:a11y-audit` audits the `.tsx` files under a path (default `src/`) for accessible
names, alt text, focus styles, keyboard traps and ARIA roles. It quotes the linter's `jsx-a11y`
findings first, then reads for what the linter cannot see, and changes nothing.

## When to reach for it

Before a release, or after a UI change:

```text
/agent-fe-nextjs:a11y-audit src/components/checkout
```

**Not for:** contrast, focus order or screen-reader output, which need a browser; check those in a
real browser instead.

## Prerequisites

- bun, with the `lint` script and `oxlint.json` that [/agent-fe-nextjs:setup](setup.md) installs;
  without them it says so and reads the files only.

## Common questions

**Does it check colour contrast?**
It flags contrast for a manual check with the two colours involved; it never states a ratio it did not compute. Contrast, focus order and screen-reader output need a browser.

## It's working if

- One line per finding: severity, `file:line`, what is wrong.

## Where it fits

Part of [agent-fe-nextjs](../../plugins/agent-fe-nextjs/README.md). A static site uses [/agent-fe-nextjs-static:a11y-audit](../agent-fe-nextjs-static/a11y-audit.md), which tests built pages.
