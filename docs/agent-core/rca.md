# rca

Command · agent-core · `/agent-core:rca [symptom]` · edits code and tests, never commits · no network, except read-only logs and queries when a bug will not reproduce locally

## What it does

`/agent-core:rca` debugs reproduction first: it reproduces the bug at the lowest level that shows it,
finds the line that causes it, and fixes it with a test that fails without the fix. It ends with the
fix and the test uncommitted in your working tree.

## When to reach for it

When a bug needs its root cause, not a guess:

```text
/agent-core:rca checkout returns 500 after login
```

`/debug <symptom>` means the same thing ([prompt-intent](prompt-intent.md) points it here).

**Not for:** shipping the fix: it stops before any commit; use [/agent-core:ship](ship.md) instead.

## Prerequisites

- The services the symptom passes through, running (database, cache, dev server); it checks them
  first.
- For a bug that shows only when signed in, a test account you create; it asks you once.

## Common questions

**Why check the stack first?**
A symptom that passes through a service that is down is not a code bug yet. It confirms the database, cache and servers answer before reading code.

**Does it look at known traps?**
Yes: it scans `.claude/anti-patterns/INDEX.md` for the symptom's keywords first.

## It's working if

- The transcript shows the new test failing before the fix and passing after it, and the report
  names the cause as `file:line`.
- `git status` lists the fix and its test as uncommitted changes.

## Where it fits

Next: [/agent-core:review](review.md) or [/agent-core:ship](ship.md). A lasting lesson goes through [/agent-core:learn-session](learn-session.md).
