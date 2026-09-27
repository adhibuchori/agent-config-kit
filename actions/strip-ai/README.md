# strip-ai action

For teams that keep agent configuration out of what they deploy. After a pull request merges into
the production branch, it:

1. removes the agent config from that branch and pushes the strip commit;
2. merges the production branch back into the development branch, keeping the development branch's
   copy of every stripped file (the merge would otherwise delete them there too);
3. verifies that the production branch tracks none of the stripped paths and that the development
   branch still has every file the strip removed.

agent-deploy's setup installs a caller when you answer `strip-ai=yes`
(`/agent-deploy:setup --answer strip-ai=yes`). The caller runs the reusable workflow
[`.github/workflows/strip-ai.yml`](../../.github/workflows/strip-ai.yml), which checks out the
production branch without storing a token and hands git the job's token through a credential helper
for the pushes.

## What it strips

`scripts/strip-paths.sh` holds the list: `.agent`, `.agents`, `.claude`, `.gemini`, `.serena`,
`.impeccable`, `_workflow-source`, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `SSOT.md`, `PRODUCT.md`,
`PRODUCT.example.md`, `DESIGN.md`, `DESIGN.example.md`, `skills-lock.json`, `.mcp.json`,
`.skillspector-baseline.yaml`, `.github/gemini.yaml` and `.github/skills`. A path that does not
exist is skipped, and nothing outside the list is removed. `.claude/` includes
`.claude/agent-config-kit.lock`, so the kit's hooks stay off on the production branch.

## Inputs

| Input | Default | What it does |
| --- | --- | --- |
| `prod-branch` | `prod` | The branch that deploys and must not carry agent config |
| `dev-branch` | `dev` | The branch that keeps it; the strip commit is merged back into it |
| `paths` | empty | Space-separated pathspecs that replace the default list |
| `extra-paths` | empty | Space-separated pathspecs added to the list; globs such as `debug*.config.ts` are git pathspecs |
| `back-merge` | `true` | `false` strips and verifies the production branch only |

## The caller

```yaml
name: Strip AI Config

on:
  pull_request:
    types: [closed]
    branches: [prod]

permissions:
  contents: read

# Not the deploy's group: a strip queued behind a deploy in a shared group can be cancelled silently.
concurrency:
  group: prod-strip-ai
  cancel-in-progress: false

jobs:
  strip-ai:
    name: Strip AI Config
    # A closed pull request that was not merged starts the workflow but runs nothing.
    if: github.event.pull_request.merged == true
    permissions:
      contents: write # push the strip commit to prod and the back-merge to dev
    uses: adhibuchori/agent-config-kit/.github/workflows/strip-ai.yml@<40-hex sha> # v1.2.0
    with: # every input is optional
      prod-branch: prod
      dev-branch: dev
```

The reusable workflow takes the action's inputs (`prod-branch`, `dev-branch`, `paths`,
`extra-paths`, `back-merge`) plus `runs-on` (empty uses the repository variable `CI_RUNNER`, then
`ubuntu-latest`) and `timeout-minutes` (15).

- Branch protection on either branch rejects the bot's push unless the workflow's token may bypass
  it.
- A back-merge that meets a real content conflict (outside the stripped paths) stops and lists the
  files; resolve it by hand.
- Each push retries three times, since anything else pushing to the branch makes a rejected push
  expected.
- No skip-CI marker is written: nothing runs on a push, and a marker on the head of the next
  promotion pull request would stop that pull request's checks.
