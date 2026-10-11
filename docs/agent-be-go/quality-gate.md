# quality-gate

Workflow · agent-be-go · `.github/workflows/quality-gate.yml` · installed by setup when you answer `ci-gate=yes` (recommended) · runs on every pull request into every branch · no secrets

## What it does

`.github/workflows/quality-gate.yml` runs agent-config-kit's `be-go-quality-gate.yml` reusable workflow on every pull request, pinned to one commit of the kit. For this Go service that is your `scripts/check/gates.list` again (format, lint, build, tidy, generated code, migrations, route literals, tests with the race detector and per-file coverage against PostgreSQL 18), the coverage floor, a database built from the migrations with the role bootstrap, the foreign-key and invalid-index queries, the migrations against the base branch, squawk, govulncheck, a committed `.env` check, gitleaks over the pull request's commits, SkillSpector when a skill, command, subagent or hook changed, and the build.

The caller passes `database: true` (false only for a service with no database at all; the tests need PostgreSQL even when the schema lives elsewhere), `pgbouncer-tests: false` (true runs the service's pool behind PgBouncer through `scripts/check/pooler.sh`) and `pgbouncer-max-prepared-statements: 200`. The job reads the checkout and nothing else: `contents: read`, no secret.

## When to reach for it

Setup writes it once a plugin release pins it; after that it runs by itself on every pull request:

```text
/agent-be-go:setup --answer ci-gate=yes
```

Make **Quality Gate** a required status check in your branch ruleset, so a red gate blocks the merge.

**Not for:** running the gates on your machine. `bash scripts/check/gates.sh` and the pre-commit hook do that.

## Prerequisites

- The files setup installed: `scripts/check/gates.sh`, `scripts/check/gates.list`, `db/roles.sql` and `.env.ci.example`.
- A committed `go.sum`, and the dummy test variables in `.env.ci.example`, never real secrets.
- A caller pinned to a released commit. One that still holds the all-zero placeholder is held back by setup until a release pins it.

## Common questions

**Why does the gate need a database?**
Every test runs against a real PostgreSQL, so the store code counts toward coverage and the role's grants and timeouts are proven, not assumed.

**How do I take a newer gate?**
`/agent-be-go:sync` offers the new pin when a plugin release moves it. Nothing moves on its own.

## It's working if

- Every pull request shows a **Quality Gate** check, and its log ends with the list of checks that passed, failed or did not run.
- A pull request that edits a merged migration, adds a foreign key without an index, or drops a file below 100% coverage turns it red.

## Where it fits

The pull-request half of the gates the pre-commit hook runs. See [/agent-be-go:setup](setup.md) and the
[CI/CD at a glance](../../README.md#cicd-at-a-glance) table.
