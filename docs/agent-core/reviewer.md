# reviewer

Agent · agent-core · `agent-core:reviewer` subagent · reads and reports only · no network

## What it does

`agent-core:reviewer` checks a diff against your repo's own rules, the numbered rules in `AGENTS.md`
and the file-type rules in `.claude/rules/`, and reports each violation with rule, file, line and
fix. It changes nothing.

## When to reach for it

`/agent-core:review` calls it when no stack reviewer is installed. You can also ask for it directly:

```text
Use the agent-core:reviewer subagent on the staged changes.
```

**Not for:** a repo with a stack plugin installed; use that plugin's reviewer, such as
[agent-fe-nextjs:reviewer](../agent-fe-nextjs/reviewer.md), instead.

## Common questions

**Why a subagent?**
It reviews in its own context, so a long diff does not crowd out your session.

## It's working if

- Findings cite a rule number or rule file for each violation.
- A clean diff gets exactly `No rule violations found in this diff.`

## Where it fits

Called by [/agent-core:review](review.md); stack plugins bring their own reviewers.
