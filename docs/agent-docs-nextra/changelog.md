# changelog

Workflow · agent-docs-nextra · `.github/workflows/changelog.yaml` · optional: setup question `ci-pipeline` (recommended no); created once, then yours · runs when a pull request into `prod` is merged, and on the application's `app-deployed` event · uses `APP_REPO_TOKEN`

## What it does

`.github/workflows/changelog.yaml` regenerates the site's generated pages after a release: the changelog at `content/changelog.mdx` and the API reference under `content/technical`, built from the application repository's `prod` branch. It commits them to `prod`, copies them to `dev`, and then calls [ci-cd](ci-cd.md) to build and deploy the site.

It runs on a merged pull request into `prod`, and on the `repository_dispatch` event `app-deployed` that the application's own deploy sends. That event is one of the two exceptions to the kit's pull-request-only rule, both named in ADR 0004.

## When to reach for it

When generators write pages into this site and CI should keep them current:

```text
/agent-docs-nextra:setup --answer generated-pages=yes --answer ci-pipeline=yes
```

Set `APP_REPO` at the top of the file to `<owner>/<app-repo>`.

**Not for:** a site whose pages are all written by hand.

## Prerequisites

- A secret `APP_REPO_TOKEN` that may read the application repository.
- The [ci-cd](ci-cd.md) workflow and its Cloudflare secrets.

## Common questions

**Why a marker cache?**
Only a marker is cached, keyed on the application commit and the generator's code: a hit means that exact tree was generated before, so the job skips the work.

## It's working if

- After a merge into `prod`, **Generate Content** is green and `prod` has a `chore: update generated content` commit when something changed.

## Where it fits

The first half of the docs pipeline; [ci-cd](ci-cd.md) is the second.
