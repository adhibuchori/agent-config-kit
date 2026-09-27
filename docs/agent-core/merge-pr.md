# merge-pr

Command · agent-core · `/agent-core:merge-pr [PR]` · only you start it · merges after you confirm · uses the network (GitHub)

## What it does

`/agent-core:merge-pr` checks a PR's readiness (checks, mergeability, unresolved threads), shows you a
summary, and on your yes merges with a merge commit. It deletes an `internal/*` head branch by name
afterwards and never deletes `dev`, `prod` or the default branch.

## When to reach for it

When a PR is approved and green:

```text
/agent-core:merge-pr 42
```

**Not for:** a PR with unresolved review threads, which it refuses to merge; use
[/agent-core:resolve-pr-review](resolve-pr-review.md) instead.

## Prerequisites

- The GitHub CLI (`gh`), signed in with permission to merge.
- `scripts/ops/pr-ready.sh`, which [/agent-core:setup](setup.md) installs.

## Common questions

**Why a merge commit and not squash?**
A merge commit keeps each commit with its own date, which is how `/agent-core:branch-cleanup` can prove a branch merged.

**A check was skipped.**
A skipped check is not a pass. It lists them; only after you confirm they skip by design does it re-check with `--allow-skipped`.

## It's working if

- A summary (branch, strategy, size, what happens to the head) appears before the merge, and the merge result after.

## Where it fits

Step 5 of the everyday flow. It uses `scripts/ops/pr-ready.sh`, which [/agent-core:setup](setup.md) installs.
