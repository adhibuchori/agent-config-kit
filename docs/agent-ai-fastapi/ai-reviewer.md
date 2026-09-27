# ai-reviewer

Agent · agent-ai-fastapi · `agent-ai-fastapi:ai-reviewer` subagent · reads and reports only · no network

## What it does

`agent-ai-fastapi:ai-reviewer` reviews the uncommitted diff of a FastAPI + LLM service against the
`AGENTS.md` rules no gate checks: layer boundaries, the problem+json error contract, provider
indirection, streaming and completion status, tests, security, typing past the `Any` ban, and one
home per identifier. With `alembic.ini` present it also applies the pipeline checks.

## When to reach for it

`/agent-core:review` hands it the diff when this plugin is installed:

```text
Use the agent-ai-fastapi:ai-reviewer subagent on the staged changes.
```

**Not for:** what the gates already fail on (formatting, types, a banned `Any`, coverage); run
`bash scripts/check/gates.sh` instead.

## Common questions

**What is provider indirection?**
Code calls an LLM through one interface, so a provider can change without touching routes or services.

## It's working if

- Each finding cites `AGENTS.md` by section and rule number (such as `§B Rule 4`), with file, line
  and fix.
- A clean diff gets exactly `No AGENTS.md violations found in this diff.`, and `git status` is the
  same before and after.

## Where it fits

Called by [/agent-core:review](../agent-core/review.md).
