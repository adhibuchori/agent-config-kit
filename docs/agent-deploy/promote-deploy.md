# promote-deploy

Command · agent-deploy · `/agent-deploy:promote-deploy [internal/<scope>]` · only you start it · uses the network (GitHub and your deploy platform)

## What it does

`/agent-deploy:promote-deploy` is the fallback promotion for when CI cannot run (a spending limit, or
every runner gone). It proves CI is down, runs the gates locally, merges `internal/<scope>` into `dev`
and `dev` into `prod` without a PR (you push), audits the production env and migrations, deploys
through your deploy adapter, verifies by time, and commits a run log of what CI still owes.

## When to reach for it

Only when the alternative is production going stale:

```text
/agent-deploy:promote-deploy internal/billing
```

Prefer `/agent-core:promote`. This command trades away every automated gate.

## Prerequisites

- The GitHub CLI (`gh`), signed in, to prove CI is down.
- Your deploy target in `.claude/OPERATIONS.md` § Deploys: the adapter operations and the migration
  commands, started from `.claude/OPERATIONS.example.md`.
- The repo's gates (`scripts/check/gates.list`), which stand in for CI, and
  `.env.production.example` for the env audit.
- `scripts/deploy/`, which [/agent-deploy:setup](setup.md) installs; for a deploy webhook,
  `DEPLOY_WEBHOOK_URL` exported in your own terminal.

## Common questions

**Who pushes?**
You do, with `! git push …`. safety-check and the deny rules refuse those pushes from Claude.

**Where does it find my platform's commands?**
`.claude/OPERATIONS.md` § Deploys, started from `.claude/OPERATIONS.example.md`. It stops and asks for any placeholder still unfilled.

## It's working if

- A run log under `promote-deploy-logs/` is committed on `dev`, with its "Owed to CI" list of what a
  runner still has to check.
- The adapter's `latest` shows a finished deployment created after your push to `prod`.

## Where it fits

The emergency twin of [/agent-core:promote](../agent-core/promote.md); verify with [/agent-deploy:verify-deploy](verify-deploy.md).
