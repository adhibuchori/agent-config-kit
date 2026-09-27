# create-pr

Command · agent-core · `/agent-core:create-pr` · only you start it · pushes a work branch and opens a PR after you confirm · uses the network (GitHub)

## What it does

`/agent-core:create-pr` drafts a pull request title and body from your repo's PR template, shows them
to you, and on your yes pushes the work branch and opens the PR into `dev` (or the default branch
when there is no `dev`).

## When to reach for it

When a work branch is ready for review:

```text
/agent-core:create-pr
```

**Not for:** a promotion from `dev` into `prod`; use [/agent-core:promote](promote.md) instead.

## Prerequisites

- The GitHub CLI (`gh`), signed in, and push access to the `origin` remote.

## Common questions

**Why into `dev`?**
The kit's branch model is `internal/<scope>` → `dev` → `prod`. A promotion into `prod` is `/agent-core:promote`.

**Can it push to `main`?**
No. safety-check refuses pushes to protected branches; it pushes your work branch only.

## It's working if

- You see the title and body first, and get the PR URL after you confirm.

## Where it fits

Step 4 of the everyday flow, after [/agent-core:commit](commit.md). Next: [/agent-core:merge-pr](merge-pr.md).
