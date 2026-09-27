# review

Command · agent-fe-nextjs-static · `/agent-fe-nextjs-static:review [base-branch]` · reads and reports · uses the network only for `git fetch`

## What it does

`/agent-fe-nextjs-static:review` reviews the staged changes, or the branch against its base, for a
static site: static-export safety, search metadata, accessibility, performance and Core Web Vitals,
security headers and design. It reports by severity and changes nothing until you pick an option at
the end.

## When to reach for it

Before a commit or a merge on a company-profile or landing site:

```text
/agent-fe-nextjs-static:review
```

**Not for:** an app with sign-in and an API; use [/agent-core:review](../agent-core/review.md)
instead.

## Prerequisites

- node and the repo's gates (`scripts/check/gates.list`), which it runs first.
- A fresh build for a change to pages, content, images, fonts, `next.config` or the headers file.

## Common questions

**Why not `/agent-core:review`?**
A static site has failure modes an app review misses: a `headers()` in `next.config` that silently does nothing under export, a hash CSP that went stale, a page that is not statically generated.

**Does it need a build?**
When the diff touches pages, content, images, fonts, `next.config` or the headers file, yes: it runs the site checks on a build newer than the change, or says it could not.

## It's working if

- The report opens with `## Status:` (`LGTM`, `Requires Changes` or `Blocked`), a count per
  severity and the gates' results.
- It ends with three options, and `git status` shows no change until you pick one.

## Where it fits

The review command of [agent-fe-nextjs-static](../../plugins/agent-fe-nextjs-static/README.md). It uses [security-guard](security-guard.md) and [seo-validator](seo-validator.md).
