# resolve-pr-review

Command · agent-core · `/agent-core:resolve-pr-review [PR] [reviewer]` · only you start it · edits after you choose · uses the network (GitHub)

## What it does

`/agent-core:resolve-pr-review` fetches a PR's review comments, judges each one against your repo's
rules, and shows a triage table. It applies the ones you accept, re-runs the gates, then replies on
every thread and summarises on the PR.

## When to reach for it

When a PR has review comments, from people or bots:

```text
/agent-core:resolve-pr-review 42
```

**Not for:** reviewing your own changes before there is a PR; use [/agent-core:review](review.md)
instead.

## Prerequisites

- The GitHub CLI (`gh`), signed in with permission to comment on the PR.
- The repo's gates (`scripts/check/gates.list`), which it re-runs after the changes.

## Common questions

**Why check suggestions against the rules?**
A review bot does not know your conventions and is often confident and wrong. A suggestion that breaks a numbered rule is marked and recommended for declining.

**Does it reply when nothing was applied?**
Yes. A declined suggestion gets a stated reason, so the next reviewer does not raise it again.

## It's working if

- Every thread gets a reply and the PR gets a summary comment; the gates pass after the changes.

## Where it fits

Between [/agent-core:create-pr](create-pr.md) and [/agent-core:merge-pr](merge-pr.md).
