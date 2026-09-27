# review

Command · agent-core · `/agent-core:review` · reads and reports, changes nothing · uses the network for `git fetch` and the dependency audit

## What it does

`/agent-core:review` reviews your staged changes, or else the branch against `origin/dev`, against
your repo's own rules, and reports findings by severity (CRITICAL, HIGH, MEDIUM, LOW). It hands the
line-by-line pass to the installed stack reviewer and runs a security pass first.

## When to reach for it

Before you commit, or to review a whole branch:

```text
/agent-core:review
```

It picks the reviewer by what is installed: `agent-fe-nextjs:reviewer`, `agent-be-hono:reviewer`,
`agent-ai-fastapi:ai-reviewer`, else `agent-core:reviewer`. A static site uses
`/agent-fe-nextjs-static:review` instead.

## Prerequisites

- The repo's gates (`scripts/check/gates.list`, or the list in `CLAUDE.md` § Quality Gates), which
  it runs instead of hand-checking formatting and types.
- Your package manager, whose dependency audit it runs on every review.

## Common questions

**Why does it read the diff "unfiltered"?**
An output wrapper can shorten a diff without saying so, and a review of a truncated diff reports "clean".

**Does it fix what it finds?**
No. It reports. `/agent-core:ship` is the command that fixes every Medium-or-higher finding.

## It's working if

- You get findings grouped by severity, each with file, line, rule and fix, and a verdict: approved, approved with warnings, or blocked.

## Where it fits

Step 2 of the everyday flow, after [/agent-core:plan](plan.md) and before [/agent-core:commit](commit.md). Uses [reviewer](reviewer.md) and [security-guard](security-guard.md).
