# workflows-lint

Workflow · agent-core · `.github/workflows/workflows-lint.yml` · installed by setup · runs on pull requests that touch `.github/` or `actions/` · no secrets

## What it does

`.github/workflows/workflows-lint.yml` checks your GitHub Actions files when a pull request changes them: actionlint (with ShellCheck over every `run:` block) for syntax and expressions, zizmor (pedantic, offline) for security problems such as template injection or a token left in the checkout, and pinact for every `uses:` being a full commit SHA whose version comment is true.

All three run in one job, and each starts even when an earlier one failed, so one run reports everything.

## When to reach for it

Setup installs it; it runs by itself when a pull request touches `.github/` or `actions/`:

```text
/agent-core:setup
```

**Not for:** a required status check. The `paths:` filter means it never reports on a pull request that leaves workflows alone, and a required check that never reports blocks the merge.

## Prerequisites

- A Linux runner with Docker: actionlint and zizmor run as pinned images.

## Common questions

**Why pin actions to a SHA?**
A tag can be moved to other code; a commit cannot. pinact checks that the `# vX.Y.Z` comment names the release that SHA really is.

## It's working if

- A pull request that changes a workflow shows a **Workflows Lint** check, and an unpinned `uses:` fails it.

## Where it fits

Guards the CI that guards everything else; see [CI/CD at a glance](../../README.md#cicd-at-a-glance).
