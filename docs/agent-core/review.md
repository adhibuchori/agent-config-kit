# review

Command · agent-core · `/agent-core:review` · reads and reports, changes nothing · uses the network for `git fetch` and the dependency audit

## What it does

`/agent-core:review` reviews your staged changes, or else the branch against `origin/dev`, on two
axes in separate subagents. The standards axis checks the code against your repo's own rules and
reports findings by severity (CRITICAL, HIGH, MEDIUM, LOW), after a security pass. The spec axis
checks the change against the spec it implements: the issue, the plan you approved, or a file you
name. Each axis has its own section and its own worst finding; the two are never merged or ranked
against each other.

## When to reach for it

Before you commit, or to review a whole branch:

```text
/agent-core:review
```

The standards axis goes to the installed stack reviewer (`agent-fe-nextjs:reviewer`,
`agent-be-hono:reviewer`, `agent-ai-fastapi:ai-reviewer`, `agent-be-go:reviewer`,
`agent-be-axum:reviewer`, `agent-ios-swiftui:reviewer`), else `agent-core:reviewer`. The spec axis
goes to [spec-reviewer](spec-reviewer.md). A static site uses `/agent-fe-nextjs-static:review`
instead.

## Prerequisites

- The repo's gates (`scripts/check/gates.list`, or the list in `CLAUDE.md` § Quality Gates), which
  it runs instead of hand-checking formatting and types.
- Your package manager, whose dependency audit it runs on every review.

## Common questions

**Why does it read the diff "unfiltered"?**
An output wrapper can shorten a diff without saying so, and a review of a truncated diff reports "clean".

**Does it fix what it finds?**
No. It reports. `/agent-core:ship` is the command that fixes every Medium-or-higher finding.

**What if the change has no issue or plan?**
The spec axis says "no spec available" and the review goes on with the standards axis alone.

**Why does every finding cite something?**
A finding that names no rule or spec line is an opinion; the subagents leave those out, and they
skip what a linter or a gate already decides.

## It's working if

- You get two sections: standards findings grouped by severity, each with file, line, rule and fix;
  spec findings in three lists, each quoting its spec line. Each section ends with its worst
  finding.
- The verdict is per axis: standards approved, approved with warnings, or blocked; spec met, partly
  met, or not checked.

## Where it fits

Step 2 of the everyday flow, after [/agent-core:plan](plan.md) and before [/agent-core:commit](commit.md). Uses [reviewer](reviewer.md), [spec-reviewer](spec-reviewer.md) and [security-guard](security-guard.md).
