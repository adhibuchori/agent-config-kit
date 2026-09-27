# Anti-Patterns Index

> Lazy-loaded knowledge base. Load only the file(s) matching your current task.
> Each file is self-contained: symptom, root cause, fix, how to catch it, scope.

## Loading Guide

### Static export and hosting

| Trigger / Task                                                                        | Load                                                 |
| ------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| Headers, redirects, a proxy or a route handler in a site with `output: 'export'`      | export-keeps-building-without-headers-proxy-or-post.md |
| Tightening the CSP to hashes, or pages that stopped hydrating after a deploy          | hash-csp-goes-stale-on-every-build.md                |
| A share card without an image, or `opengraph-image.tsx` under export                  | opengraph-image-has-no-extension-in-export.md        |
| Setting `openGraph` in a page's metadata, or a share card that lost its image        | page-opengraph-drops-the-site-share-image.md         |
| Rate limiting a form endpoint                                                         | in-memory-rate-limit-on-serverless.md                |

### Tooling and git

| Trigger / Task                                                                     | Load                                   |
| ---------------------------------------------------------------------------------- | -------------------------------------- |
| Any `bun build` or `bun test` invocation, or a mass test failure sharing one error | bun-build-vs-bun-run-build.md          |
| Local Next.js dev/build on macOS (Node.js 25+)                                     | nodejs-25-webstorage-ssr.md            |
| Applying any patch, or building one with `git diff --no-index`                     | git-apply-check-passes-then-deletes.md |
| Committing while another agent session shares the checkout                         | shared-git-index-across-sessions.md    |

### Styling and layout

| Trigger / Task                                                               | Load                                   |
| ---------------------------------------------------------------------------- | -------------------------------------- |
| A Tailwind utility with no effect against a hand-written rule                | unlayered-css-beats-tailwind-layers.md |
| Smooth scroll to an anchor that does nothing, or snaps back while content loads | smooth-scroll-races-layout-shift.md |
| A glass surface whose blur does nothing, or a hand-written `-webkit-` property | lightningcss-keeps-only-the-prefixed-backdrop-filter.md |

## When to add a new entry

A new anti-pattern qualifies when:

- It cost real debugging time (>30 min)
- The root cause is non-obvious from reading code/docs
- Same trap is likely to recur (vendor bug, environment quirk, tooling gotcha)

Write it with the shape the others use: `**Applies to:**` and `**Status:**` lines, then Symptom,
Root cause, Fix, How to catch it and Scope. Use neutral names in examples, and state the lesson
rather than the date or the story it came from. Add its row here in the same change: a file with
no row is never loaded, and a row with no file sends the reader nowhere.

If the bug gets fixed upstream, **delete the file** — don't leave stale entries.

## File naming convention

`<scope>-<short-description>.md` — kebab-case, descriptive enough to skip without opening.
