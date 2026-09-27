# a11y-audit

Command · agent-fe-nextjs-static · `/agent-fe-nextjs-static:a11y-audit [route …]` · reads and reports · no network (serves the build locally)

## What it does

`/agent-fe-nextjs-static:a11y-audit` audits the built site in a real browser with your project's own
pa11y-ci or axe, adds the source lint, then reads for what automated checkers miss (keyboard,
structure, focus). It changes nothing.

## When to reach for it

Before a release and after a design change:

```text
/agent-fe-nextjs-static:a11y-audit
/agent-fe-nextjs-static:a11y-audit / /contact
```

It runs `node scripts/check/a11y.mjs`, which serves the build on 127.0.0.1.

**Not for:** what only a person can judge (screen-reader output, a real phone); have someone test
those instead, from the list the report ends with.

## Prerequisites

- node and a build of the site (`out/`, or `.next/server/app/`); it asks you to build when there is
  none or the source changed after it.
- `pa11y-ci` or `@axe-core/cli` as a dev dependency (axe also needs a ChromeDriver that matches
  Chrome). Nothing is downloaded.

## Common questions

**It exits 2.**
No checker is installed, no browser, or no build. Nothing is downloaded: add `pa11y-ci` (brings its own browser) or `@axe-core/cli` as a dev dependency.

## It's working if

- `node scripts/check/a11y.mjs` exits 0, and the report lists no `CRITICAL` finding.

## Where it fits

Part of [agent-fe-nextjs-static](../../plugins/agent-fe-nextjs-static/README.md); also a step of [/agent-fe-nextjs-static:launch-checklist](launch-checklist.md).
