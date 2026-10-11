# spec-reviewer

Agent · agent-core · `agent-core:spec-reviewer` subagent · reads and reports only · no network

## What it does

`agent-core:spec-reviewer` checks a diff against the spec it was meant to implement: the linked
issue, the plan you approved, or a spec file you name. It reports three lists, each finding quoting
the spec line it rests on: requirements missing or met only in part, behaviour no spec line asked
for, and requirements implemented wrongly. It changes nothing.

## When to reach for it

`/agent-core:review` runs it as the spec axis, beside the standards reviewer, and prints its report
under its own heading. You can also ask for it directly:

```text
Use the agent-core:spec-reviewer subagent on the staged changes, against issue 42.
```

**Not for:** how the code is written (the standards reviewer's question), or anything a linter or a
gate already decides.

## Common questions

**What if there is no spec?**
It says "no spec available" and stops. It never infers requirements from the code, since the code
would then always match them.

**Why a separate subagent from the standards reviewer?**
One reviewer asked both questions lets one answer crowd out the other. Two subagents in their own
contexts keep both reports whole, and the review never merges or reranks them.

## It's working if

- Every finding quotes a line of the spec and names the file and line of the diff.
- The report ends with the count per list and the single worst finding.

## Where it fits

Called by [/agent-core:review](review.md) next to [reviewer](reviewer.md) or the stack's reviewer.
