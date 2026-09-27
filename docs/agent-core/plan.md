# plan

Command · agent-core · `/agent-core:plan [what to build]` · reads only, writes nothing · network only to look up docs (such as through Context7)

## What it does

`/agent-core:plan` writes an implementation plan before any code: scope, ordered tasks, data and
migrations, risks and open questions. It researches what already exists first, then waits for your
yes. It writes no file.

## When to reach for it

Before you build anything that touches more than one file, a schema or an env variable:

```text
/agent-core:plan add a password-reset flow
```

A stack plugin can add its own planner, such as `/agent-fe-nextjs:plan-fullstack` for a change that
spans a frontend and its API.

**Not for:** a bug whose cause is unknown; use [/agent-core:rca](rca.md) instead.

## Common questions

**Why does it read SSOT.md and AGENTS.md?**
They hold the architecture facts and the numbered rules of your repo; a plan that ignores them gets rejected in review.

**Can I skip the confirmation?**
Answer "go" to the CONFIRMATION list; it does not start implementing before that.

## It's working if

- You get a plan with SCOPE, TASKS, DATA, RISKS and CONFIRMATION sections, and `git status` shows
  no change.

## Where it fits

Step 1 of the everyday flow. Next: write the code, then [/agent-core:review](review.md).
