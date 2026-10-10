# quality-gate

Workflow · agent-be-axum · `.github/workflows/quality-gate.yml` · installed by setup when you answer `ci-gate=yes` (recommended), once a release pins it · runs on every pull request into every branch · no secrets

## What it does

`.github/workflows/quality-gate.yml` runs agent-config-kit's `be-axum-quality-gate.yml` reusable workflow on every pull request, pinned to one commit of the kit. For this Rust + Axum service that is the pinned toolchain with no downloads at build time, your `scripts/check/gates.list` with a PostgreSQL service for the database tier, the coverage floor, migrations applied to an empty database, the offline query cache check, unindexed foreign keys, migrations against the base branch, cargo-deny, the exported OpenAPI document, the release build, a committed `.env` check, gitleaks over the pull request's commits and SkillSpector when a skill, command, subagent or hook changed. With `pgbouncer-tests: true` it also runs `tests/pooler` through PgBouncer.

A check that cannot run fails the gate unless you pass `strict: false`, so a skipped secret scan never looks like a passed one. The job reads the checkout and nothing else: `contents: read`, no secret, and the checkout keeps no token.

## When to reach for it

Setup writes it; after that it runs by itself on every pull request:

```text
/agent-be-axum:setup --answer ci-gate=yes
```

Make **Quality Gate** a required status check in your branch ruleset, so a red gate blocks the merge. Every input is optional; set them under `with:` in the caller, for example `database: false` when another repo owns the schema, or `pgbouncer-tests: true`. The [reusable workflows](../../README.md#ci-reusable-workflows) section of the README lists them.

**Not for:** running the gates on your machine. `bash scripts/check/gates.sh` and the pre-commit hook do that on the files you staged.

## Prerequisites

- The files setup installed: `scripts/check/gates.sh`, `scripts/check/gates.list` and the check scripts it names.
- A committed `Cargo.lock`, and the dummy variables the tests need in the committed `env-file` (default `.env.ci.example`), never real secrets.
- A caller pinned to a released commit. This plugin's first release ships the caller with the all-zero placeholder, so setup holds it back until a release pins it.

## Common questions

**Which runner does it use?**
The repository variable `CI_RUNNER_FAST`, then `CI_RUNNER`, then `ubuntu-latest`: it is the job a person waits on, so it takes the fast pool first. The database tier needs a Linux runner. See `.claude/CI-RUNNERS.example.md`.

**How do I take a newer gate?**
`/agent-be-axum:sync` offers the new pin when a plugin release moves it. Nothing moves on its own.

## It's working if

- Every pull request shows a **Quality Gate** check, and its log ends with the list of checks that passed, failed or did not run.
- A pull request that edits a merged migration, adds a real-looking secret, or leaves a file below 100% coverage turns it red.

## Where it fits

The pull-request half of the gates the pre-commit hook runs. See [/agent-be-axum:setup](setup.md) and the
[CI/CD at a glance](../../README.md#cicd-at-a-glance) table.
