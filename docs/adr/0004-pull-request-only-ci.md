# 4. CI runs on pull requests only: no push triggers, no schedules, no Dependabot

- Status: accepted
- Date: 2026-09-26

## Context

Push-triggered CI runs the same checks again after a pull request already ran them, and scheduled
jobs and Dependabot spend runner minutes and open pull requests nobody asked for. Workflows that run
with elevated context (`pull_request_target`, `workflow_run`) on pull-request code are a known
injection risk.

## Decision

- Every workflow in this repo and in every template is triggered by pull-request events or
  `workflow_call` only. No `push:`, `schedule:`, `pull_request_target`, `workflow_run` or
  `workflow_dispatch`; no Dependabot.
- Every `uses:` is pinned to a full commit SHA with a `# vX.Y.Z` comment; top-level permissions
  are `contents: read`; checkouts use `persist-credentials: false`; secrets are passed by name,
  never `secrets: inherit`; event data never appears in `${{ }}` inside `run:`.
- Dependency freshness is checked when it matters: dependency review on each pull request, and
  `pinact`, `zizmor` and `actionlint` when a workflow changes. OpenSSF Scorecard runs locally before
  a release rather than on a schedule.
- **One exception.** agent-docs-nextra's optional `changelog.yaml` also accepts
  `repository_dispatch`: the application a docs site documents sends that event after its own
  release, so the docs pages follow the release without a push trigger or a schedule. The event
  can only be sent with a token that has write access to the docs repository, and the job's `if:`
  names it explicitly. No other workflow may use it, and `issue_comment` is never allowed.
- `scripts/workflow-policy.py` enforces the trigger rules in CI, with that one exception named by
  file.

## Consequences

- Nothing runs unless someone opens or updates a pull request.
- Pinned actions do not update themselves; a maintainer raises pins deliberately, and pinact
  verifies the version comments.
- The OpenSSF Scorecard checks for Dependabot and scheduled runs score lower; that is accepted and
  documented rather than gamed.
