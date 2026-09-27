# quality-gate

Workflow · agent-fe-nextjs · `.github/workflows/quality-gate.yaml` · installed by setup · runs on every pull request into `dev`, `prod`, `main` and `master` · no secrets

## What it does

`.github/workflows/quality-gate.yaml` runs agent-config-kit's `fe-nextjs-quality-gate.yml` reusable workflow on every pull request, pinned to one commit of the kit. For this Next.js app that is an install from the lockfile, the API client generation when the repo has an orval config, your `scripts/check/gates.list`, the coverage floor (100), a committed `.env` check, the added-line scans, gitleaks over the pull request's commits, the audit, SkillSpector when a skill, command, subagent or hook changed, the production build, and no source maps in `.next/static`.

A check that cannot run fails the gate unless you pass `strict: false`, so a skipped secret scan never looks like a passed one. The job reads the checkout and nothing else: `contents: read`, no secret, and the checkout keeps no token.

## When to reach for it

Setup writes it; after that it runs by itself on every pull request:

```text
/agent-fe-nextjs:setup
```

Make **Quality Gate** a required status check in your branch ruleset, so a red gate blocks the merge. Every input is optional; set them under `with:` in the caller, for example `coverage-threshold` or `runs-on`. The [reusable workflows](../../README.md#ci-reusable-workflows) section of the README lists them.

**Not for:** running the gates on your machine. `bash scripts/check/gates.sh` and the pre-commit hook do that on the files you staged.

## Prerequisites

- The files setup installed: `scripts/check/gates.sh` and `scripts/check/gates.list`.
- A committed lockfile, and for the build any dummy variables in the committed `env-file` (default `.env.ci.example`), never real secrets.
- A caller pinned to a released commit. One that still holds the all-zero placeholder is held back by setup until a release pins it.

## Common questions

**Which runner does it use?**
The repository variable `CI_RUNNER_FAST`, then `CI_RUNNER`, then `ubuntu-latest`: it is the job a person waits on, so it takes the fast pool first. See `.claude/CI-RUNNERS.example.md`.

**How do I take a newer gate?**
`/agent-fe-nextjs:sync` offers the new pin when a plugin release moves it. Nothing moves on its own.

## It's working if

- Every pull request shows a **Quality Gate** check, and its log ends with the list of checks that passed, failed or did not run.
- A pull request that adds a real-looking secret, or drops coverage below the floor, turns it red.

## Where it fits

The pull-request half of the gates the pre-commit hook runs. See [/agent-fe-nextjs:setup](setup.md) and the
[CI/CD at a glance](../../README.md#cicd-at-a-glance) table.
