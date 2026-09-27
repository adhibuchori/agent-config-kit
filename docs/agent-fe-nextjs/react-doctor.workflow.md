# react-doctor

Workflow · agent-fe-nextjs · `.github/workflows/react-doctor.yml` · optional: setup question `react-doctor-ci` (recommended no) · runs on pull requests into `dev`, `prod`, `main` or `master` · advisory, never fails the check

## What it does

`.github/workflows/react-doctor.yml` runs the React Doctor action on each pull request and reports security, performance, correctness, accessibility and architecture findings as review comments on the changed lines, one summary comment and a commit status. It never fails the check. The [react-doctor skill](react-doctor.md) runs the same CLI locally, with its reporting turned off.

The action and the CLI are pinned (the action to a commit, the CLI to `0.9.14`), so a run changes only when this file does.

## When to reach for it

When you want React findings in the pull request itself:

```text
/agent-fe-nextjs:setup --answer react-doctor-ci=yes
```

**Not for:** blocking a merge. Use the quality gate for that.

## Prerequisites

- Nothing to configure: it uses the job's own token, with write access to pull-request comments, issue comments and statuses only.

## Common questions

**Does it send anything to the vendor?**
Yes. The action runs the CLI with its defaults, which report diagnostics to the vendor's score service. That is why setup recommends **no**; answer yes only if that is acceptable for this repository.

**Which runner?**
`CI_RUNNER`, then `ubuntu-latest`: nobody waits on an advisory check, so it stays off the fast pool.

## It's working if

- A pull request shows a **React Doctor** commit status and a summary comment with its findings.

## Where it fits

An advisory check next to the [quality gate](quality-gate.md).
