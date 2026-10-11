# reviewer

Agent · agent-be-axum · `agent-be-axum:reviewer` subagent · reads and reports only · no network

## What it does

`agent-be-axum:reviewer` reviews the diff of a Rust + Axum service against your `AGENTS.md` and
the rules under `.claude/rules`: layering by module privacy, the error contract, sqlx queries and
migrations, and tests. It is the standards axis of a review: it reports each breach with its rule
number, file, line and fix, and changes no file.

## When to reach for it

`/agent-core:review` hands it the diff when this plugin is installed:

```text
Use the agent-be-axum:reviewer subagent on the staged changes.
```

It skips what clippy, rustfmt, the compiler and the gates already refuse, and looks for what they
cannot see: a query in a loop, a list without a bound, a foreign key without an index, a
transaction that calls the network, an error without its code, a test that replaces a module of the
crate. Where the payload contract is adopted, it also looks for a key or an opened body in a log
line, a route merged after the payload layer, and an exemption reasoned by sensitivity.

**Not for:** a repo without an `AGENTS.md`, where it stops; use
[agent-core:reviewer](../agent-core/reviewer.md) instead.

## Common questions

**Does it check whether the change does what the task asked?**
No. That is the spec axis, a separate review; this one judges how the code is written.

## It's working if

- Each finding cites an `AGENTS.md` rule number, file and line, with the quoted hunk and a fix.
- A clean diff gets exactly `No AGENTS.md violations found in this diff.`

## Where it fits

Called by [/agent-core:review](../agent-core/review.md).
