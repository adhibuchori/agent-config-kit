# learn-session

Command · agent-core · `/agent-core:learn-session` · edits files under `.claude/` · no network

## What it does

`/agent-core:learn-session` captures what this session taught and writes each lesson into the check,
rule, reference or anti-pattern that will load again. It writes no feedback or log files.

## When to reach for it

When the session hit a trap worth never hitting again, or you stated a preference that should
stick:

```text
/agent-core:learn-session
```

**Not for:** a record of what happened this session; use
[/agent-core:checkpoint-summary](checkpoint-summary.md) instead.

## Common questions

**Why not a notes file?**
Notes files pile up where nothing reads them. A lesson changes behaviour only in a file that loads when it matters.

**Does it commit?**
No, unless you ask.

## It's working if

- It reports each file it wrote and the line it added or changed, and `git status` shows those
  files under `.claude/rules/`, `.claude/anti-patterns/`, `.claude/OPERATIONS.md` or
  `scripts/check/`.
- When nothing is worth keeping, it says so and `git status` shows no change.

## Where it fits

After [/agent-core:rca](rca.md) or a hard session. [/agent-core:checkpoint-summary](checkpoint-summary.md) is its handover twin.
