# codeql

Workflow · agent-core · `.github/workflows/codeql.yml` · installed by setup · runs on every pull request · no secrets

## What it does

`.github/workflows/codeql.yml` runs GitHub's CodeQL code scanning on every pull request, for the languages the repository holds: GitHub Actions always, JavaScript and TypeScript when there is a `tsconfig.json`, Python when there is a `pyproject.toml`. Nothing is compiled and no project code runs (build mode `none`).

It is the advanced setup on purpose: GitHub's default setup adds a weekly scheduled scan, and the kit runs nothing on a schedule.

## When to reach for it

Setup installs it; it runs by itself on every pull request:

```text
/agent-core:setup
```

**Not for:** a private repository without GitHub Code Security. There the jobs skip until you set the repository variable `CODE_SECURITY` to `true`.

## Prerequisites

- A public repository, or a private one with GitHub Code Security and `CODE_SECURITY=true`.

## Common questions

**Where do the results show?**
As the pull request's code scanning check, with annotations on the lines it changed.

**Which runner?**
`CI_RUNNER`, then `ubuntu-latest`.

## It's working if

- Each pull request shows **Analyze (actions)**, plus one job per detected language, and a **CodeQL** check.

## Where it fits

Supply-chain and code scanning next to [dependency-review](dependency-review.md) and
[workflows-lint](workflows-lint.md); see [CI/CD at a glance](../../README.md#cicd-at-a-glance).
