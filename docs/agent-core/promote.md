# promote

Command · agent-core · `/agent-core:promote` · only you start it · merges and deploys with your pushes · uses the network (GitHub and your deploy platform)

## What it does

`/agent-core:promote` takes `internal/<scope>` through a PR into `dev`, then a promotion PR into
`prod`, audits the production env and migrations, and verifies the deploy by timestamp. It does not
report success until production has actually changed.

## When to reach for it

When a branch should reach production:

```text
/agent-core:promote
```

**Not for:** merging one reviewed PR into `dev`; use [/agent-core:merge-pr](merge-pr.md) instead.

## Prerequisites

- The GitHub CLI (`gh`), signed in with permission to merge.
- Your deploy target in `.claude/OPERATIONS.md` § Deploys: the platform, the adapter operations
  (`read-env`, `latest`, `trigger`, `backup`) as your platform's CLI, API or MCP server runs them,
  and the migration commands. Start it from `.claude/OPERATIONS.example.md`, which setup installs;
  it asks for any value still missing.
- `.env.production.example`, for the production env audit (without it the audit is reported as not
  run), and the repo's gates (`scripts/check/gates.list`).

## Common questions

**Who pushes to `dev` and `prod`?**
You do. safety-check refuses those pushes from Claude however they are asked, so it asks you to type `! git push …` and waits.

**CI is down. Can I still promote?**
Use `/agent-deploy:promote-deploy` from the optional agent-deploy plugin, and only when the alternative is production going stale.

## It's working if

- Both PRs show as merged on GitHub, and the report names a deployment id whose created-at time is
  later than the `dev` → `prod` merge.

## Where it fits

The last step after [/agent-core:merge-pr](merge-pr.md). Then [/agent-core:branch-cleanup](branch-cleanup.md).
