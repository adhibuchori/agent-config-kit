# checkpoint

Command · agent-core · `/agent-core:checkpoint [description]` · only you start it · commits locally, never pushes · no network

## What it does

`/agent-core:checkpoint` makes a local safety commit of the files this session wrote, by pathspec,
with an ISO timestamp, before a risky change. It never pushes.

## When to reach for it

Before a refactor or an experiment you may want to roll back:

```text
/agent-core:checkpoint before splitting the auth module
```

**Not for:** sharing work or asking for review: it never pushes; use
[/agent-core:create-pr](create-pr.md) instead.

## Common questions

**Does it run the pre-commit gate?**
Yes. It never skips it (safety-check refuses `--no-verify` anyway).

**It left a file out.**
It stages only the paths this session wrote and names any other changed file it left out.

## It's working if

- It prints the commit hash and the files it carried, and names any changed file it left out.
- `git log -1 --stat` shows a `chore: checkpoint — <description> [<timestamp>]` commit holding only
  this session's files.

## Where it fits

A safety net inside the flow. [/agent-core:ship](ship.md) reviews and pushes later.
