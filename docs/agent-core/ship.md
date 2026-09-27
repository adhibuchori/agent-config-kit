# ship

Command · agent-core · `/agent-core:ship` · only you start it · stages everything, fixes findings, commits and pushes a work branch · uses the network (GitHub)

## What it does

`/agent-core:ship` takes finished work from "written" to "pushed" in one pass: it stages every
change, runs `/agent-core:review` and `/security-review`, fixes every CRITICAL, HIGH and MEDIUM
finding, re-runs the gates, then commits and pushes the current `internal/*` branch. It refuses to
run on `dev` or `prod`.

## When to reach for it

When you want the whole working tree reviewed, fixed and pushed without triaging each finding:

```text
/agent-core:ship
```

**Not for:** a checkout another session is writing in right now; use
[/agent-core:commit](commit.md) instead, which stages by name.

## Prerequisites

- Push access to the `origin` remote: it ends with `git push`.
- The repo's gates (`scripts/check/gates.list`), which it re-runs until they pass.

## Common questions

**It stages everything. Is that safe?**
It is the one command that does, and it guards it three ways: protected files stay out, a nested repository stays out, and the staged set is compared with a snapshot before the commit, so nothing joins unseen.

**Can it push to `main`?**
No. It refuses on `dev`, `prod` and the default branch, and safety-check refuses protected pushes anyway.

## It's working if

- The report lists every gate's final state, what was auto-staged, each finding with its fix, and
  the commit SHA.
- `git log -1 origin/<your branch>` shows that SHA: the `internal/*` branch is pushed.

## Where it fits

The one-pass alternative to [review](review.md) → [commit](commit.md) → push. Next: [/agent-core:create-pr](create-pr.md).
