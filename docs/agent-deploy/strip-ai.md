# strip-ai

Workflow · agent-deploy · `.github/workflows/strip-ai.yml` · optional: setup question `strip-ai` (recommended no) · runs when a pull request into `prod` is merged · uses the job's own token to push

## What it does

`.github/workflows/strip-ai.yml` keeps agent configuration out of what you deploy. When a pull request is merged into `prod`, it calls agent-config-kit's `strip-ai.yml` reusable workflow, which removes `.claude/`, `AGENTS.md`, `CLAUDE.md`, `.mcp.json` and the rest of the list from `prod`, merges `prod` back into `dev` while keeping `dev`'s copy of every stripped file, and then checks both branches.

The checkout keeps no token: git gets the job's token for its pushes through a credential helper that reads it from the environment.

## When to reach for it

When production must not carry agent instructions:

```text
/agent-deploy:setup --answer strip-ai=yes
```

**Not for:** a repository with one long-lived branch. It needs a production branch and a development branch.

## Prerequisites

- `prod` and `dev` branches, and a branch ruleset that lets the workflow's token push to both (or no ruleset on them).
- A caller pinned to a released commit (setup holds a placeholder-pinned one back).

## Common questions

**Does it fight with the deploy?**
No. It runs in its own queue, `prod-strip-ai`, so a queued strip is never cancelled by a deploy.

**What if the back-merge conflicts?**
A conflict outside the stripped paths stops the job and lists the files; resolve it by hand.

## It's working if

- After a merge into `prod`, **Strip AI Config** is green, `prod` has no `.claude/` and `dev` still has it.

## Where it fits

Runs on the same merge as [deploy](deploy.md). [/agent-deploy:promote-deploy](promote-deploy.md) does the same
strip by hand when CI cannot run.
