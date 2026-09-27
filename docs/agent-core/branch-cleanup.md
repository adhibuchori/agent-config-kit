# branch-cleanup

Command · agent-core · `/agent-core:branch-cleanup` · only you start it · deletes merged branches after you confirm · uses the network (GitHub)

## What it does

`/agent-core:branch-cleanup` deletes every merged branch on the remote and locally, except `dev`,
`prod`, the default branch and the heads of open PRs, once you confirm the list. Unmerged branches
are reported and kept.

## When to reach for it

After a promotion:

```text
/agent-core:branch-cleanup
```

**Not for:** deleting one branch right after its PR merges; use [/agent-core:merge-pr](merge-pr.md)
instead, which deletes an `internal/*` head by name.

## Prerequisites

- The GitHub CLI (`gh`), signed in with permission to delete branches in the repository.
- PRs merged with merge commits, the kit's way: a squash-merged branch still looks unmerged, so it
  is reported and kept.

## Common questions

**How does it know a branch merged?**
It proves it from the merge commits, which is why the kit merges with merge commits and never squashes.

**Can I undo a deletion?**
The deletion itself is the one irreversible step, which is why it shows the list and waits for you.

## It's working if

- Before deleting, it shows a table of branches, each with its `ahead_by` count and `delete` or
  `keep`, and waits for your yes.
- Its report ends with the remote branch list: `dev`, `prod`, the default branch, open-PR heads and
  any branch it reported as unmerged. `git ls-remote --heads origin` shows the same list.

## Where it fits

After [/agent-core:promote](promote.md).
