# ci-cd

Workflow · agent-docs-nextra · `.github/workflows/ci-cd.yaml` · optional: setup question `ci-pipeline` (recommended no) · runs only when [changelog](changelog.md) calls it · uses `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`

## What it does

`.github/workflows/ci-cd.yaml` builds the static export of `prod` (`next build`, then the search index) and uploads it to an assets-only Cloudflare Worker. It starts only from [changelog](changelog.md), after the generated pages have landed, so a deploy never ships the pages from before that commit.

The job that publishes uses no dependency cache, so a poisoned cache entry cannot ship.

## When to reach for it

Installed with the docs pipeline:

```text
/agent-docs-nextra:setup --answer ci-pipeline=yes
```

**Not for:** running on its own; it has no trigger besides the call.

## Prerequisites

- `wrangler.jsonc`, made from the installed `wrangler.example.jsonc`.
- Secrets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`.

## Common questions

**Which runner?**
`CI_RUNNER_FAST`, then `CI_RUNNER`, then `ubuntu-latest`: the install and build take more than a minute, so the faster pool pays here.

## It's working if

- **Build & Deploy** is green after **Generate Content**, and the live site shows the new pages.

## Where it fits

The second half of the docs pipeline, after [changelog](changelog.md).
