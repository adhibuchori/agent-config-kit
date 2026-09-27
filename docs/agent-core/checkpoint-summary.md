# checkpoint-summary

Command · agent-core · `/agent-core:checkpoint-summary [domain]` · prints; optional local log · no network

## What it does

`/agent-core:checkpoint-summary` summarises the session for a handover: what was done, what is
pending, what comes next. It can also save a longer log under `.claude/session-logs/`, which setup
adds to `.gitignore`.

## When to reach for it

At the end of a session, or before handing work to someone else:

```text
/agent-core:checkpoint-summary auth
```

**Not for:** lessons that should change the next session; use
[/agent-core:learn-session](learn-session.md) instead.

## Common questions

**Is the log committed?**
No. `.claude/session-logs/` is gitignored: a local handoff only.

**Where do lessons go?**
Not in the log. Use `/agent-core:learn-session`, which writes them where they load again.

## It's working if

- The transcript shows a short summary: branch, what was done, key decisions, files changed and
  what is next.
- When you asked for the log, `.claude/session-logs/<date>-<domain>.md` exists and `git status`
  does not list it.

## Where it fits

Records what happened; [/agent-core:learn-session](learn-session.md) records what should change.
