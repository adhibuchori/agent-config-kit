# check-fix

Command · agent-core · `/agent-core:check-fix [files]` · Claude may start it · changes files, never commits · no network

## What it does

`/agent-core:check-fix` runs the repo's quality gates, fixes each failure at its cause (format and
lint twice, then types, build, tests in CI's environment, schema and stack checks), and re-runs the
whole list until every gate passes or only a decision is left.

## When to reach for it

A gate is red before a commit, or a working tree needs to get green:

```text
/agent-core:check-fix
/agent-core:check-fix src/lib/money.ts src/lib/money.test.ts
```

**Not for:** committing or reviewing; it never commits. Use [/agent-core:commit](commit.md) after
it, or [/agent-core:ship](ship.md) for the whole review-fix-commit-push pass.

## Common questions

**Will it add a lint-disable comment to get past a gate?**
No. It fixes the cause; a narrow suppression needs a reason on the line and your agreement first.

**Can it lower a coverage threshold?**
No. It deletes a dead branch or tests the live one.

## It's working if

- It ends with a table of gates, each PASS, or FAIL with the reason it needs you.
- `bash scripts/check/gates.sh` passes afterwards.

## Where it fits

Before [/agent-core:commit](commit.md). [/agent-core:review](review.md) judges what no gate can.
