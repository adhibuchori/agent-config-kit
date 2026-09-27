# commit

Command · agent-core · `/agent-core:commit` · only you start it · runs the gates, drafts only · no network of its own

## What it does

`/agent-core:commit` runs your quality gates, inspects what is staged, and drafts a commit message in
your repo's format. It does not commit: you do, by pathspec.

## When to reach for it

When staged work is ready:

```text
/agent-core:commit
```

It runs `bash scripts/check/gates.sh` when the repo has `scripts/check/gates.list`, and refuses to go
on from a red gate.

**Not for:** making the commit itself: it only drafts; use [/agent-core:ship](ship.md) instead to
review, commit and push in one pass.

## Prerequisites

- The repo's gates and the tools they call: `scripts/check/gates.list`, or the list in `CLAUDE.md`
  § Quality Gates. With neither, you still get a draft and a note that no gate ran.

## Common questions

**Why never `git add -A`?**
It also takes files you did not write: another session's half-finished edit or a forgotten secret. Only `/agent-core:ship` stages everything, because it runs the guards that make that safe.

**What will it refuse to include?**
Real `.env*` files and hand-edited generated output (`generatedPaths`, `migrationsDirs`).

## It's working if

- The transcript shows the gates passing, then a drafted `type: subject` message.
- `git log` gains nothing until you run `git commit -- <paths>` yourself.

## Where it fits

Step 3 of the everyday flow. [post-commit](post-commit.md) then shows what the commit carried; next is [/agent-core:create-pr](create-pr.md).
