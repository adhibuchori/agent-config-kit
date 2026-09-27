# reviewer

Agent · agent-be-hono · `agent-be-hono:reviewer` subagent · reads and reports only · no network

## What it does

`agent-be-hono:reviewer` reviews the uncommitted diff of a Bun + Hono + Drizzle API against your
`AGENTS.md`: layer boundaries, the error contract, database access, query shape and indexes, tests
and code quality. It reports each violation with its rule number and changes no file.

## When to reach for it

`/agent-core:review` hands it the diff when this plugin is installed:

```text
Use the agent-be-hono:reviewer subagent on the staged changes.
```

**Not for:** a repo without an `AGENTS.md`, where it stops; use
[agent-core:reviewer](../agent-core/reviewer.md) instead.

## Common questions

**Does it check indexes?**
It reads query shape against the indexes each foreign key and filter needs; the CI gate also runs an index-coverage check.

## It's working if

- Each finding cites an `AGENTS.md` rule number, file and line.
- A clean diff gets exactly `No AGENTS.md violations found in this diff.`

## Where it fits

Called by [/agent-core:review](../agent-core/review.md).
