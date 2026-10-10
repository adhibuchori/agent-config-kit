# reviewer

Agent · agent-be-go · `agent-be-go:reviewer` subagent · reads and reports only · no network

## What it does

`agent-be-go:reviewer` reviews the diff of a Go HTTP service against your `AGENTS.md` and the rules
under `.claude/rules`: layering, the error contract, database access, query shape and indexes, and
tests. It reports each breach with its rule number, file, line and fix, and changes no file. It
skips what golangci-lint, the compiler and the gates already fail.

## When to reach for it

`/agent-core:review` hands it the diff as the standards axis of a review, next to the spec axis:

```text
Use the agent-be-go:reviewer subagent on the staged changes.
```

**Not for:** whether the change does what was asked (the spec reviewer's axis), or a repo without
the rule index; use [agent-core:reviewer](../agent-core/reviewer.md) there.

## Common questions

**Why does it not report a long file or a bare `//nolint`?**
golangci-lint already fails those in the gate. The reviewer looks for what no machine checks: a
handler doing a service's work, a query in a loop, a foreign key without its index, an upstream
code that got lost, a test that replaces a package of this repo.

**Does it review generated code?**
No. A hand edit to a generated file is itself the finding.

## It's working if

- Each finding cites an `AGENTS.md` rule number, file and line, with the quoted hunk and the fix.
- The report ends with the count of findings and the worst one.

## Where it fits

Called by [/agent-core:review](../agent-core/review.md) in a repo set up with
[agent-be-go](../../plugins/agent-be-go/README.md).
