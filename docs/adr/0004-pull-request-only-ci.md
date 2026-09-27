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
  names it explicitly. No other workflow may use it.
- **A second exception, added in 1.2.0** (see the amendment below): a template's
  `deepseek-review.yml` also accepts `issue_comment`, for the `/ask-deepseek` command, in one
  checked shape.
- `scripts/workflow-policy.py` enforces the trigger rules in CI, with both exceptions named.

## Consequences

- Nothing runs unless someone opens or updates a pull request.
- Pinned actions do not update themselves; a maintainer raises pins deliberately, and pinact
  verifies the version comments.
- The OpenSSF Scorecard checks for Dependabot and scheduled runs score lower; that is accepted and
  documented rather than gamed.

## Amendment (2026-09-28): the `/ask-deepseek` comment trigger

The optional DeepSeek review reviews a pull request when it opens. Asking again after new commits
needs a trigger a person can pull on demand, and on GitHub that is a comment. `issue_comment` is
risky in general: it runs from the default branch with the repository's secrets and a write token,
for a comment anyone can post, including on a pull request from a fork. A workflow that checks out
the pull request's code there hands that code the secrets.

We allow it in one shape only, and `scripts/workflow-policy.py` fails any other:

- only a template's `.github/workflows/deepseek-review.yml`, with `issue_comment` limited to
  `types: [created]`;
- top-level permissions `contents: read`; every job is a call to this repository's
  `deepseek-review.yml` and nothing else, holding `contents: read` and `pull-requests: write`;
- every job's `if:` requires a comment on a pull request (`github.event.issue.pull_request`) by the
  repository's `OWNER`, a `MEMBER` or a `COLLABORATOR`, and no other association;
- the called workflow checks nothing out: the action reads the pull request and its files over the
  REST API as data and runs no code from it. It also skips a pull request from a fork on every
  event, and the reusable workflow repeats the association guard.

What remains: a trusted commenter spends API tokens (bounded by the diff and answer caps), and the
diff can steer what the model writes in its one comment. The model has no tools and never sees a
secret, and the comment says it is advisory. A comment that is not the command gets a concurrency
group of its own, so it can never cancel a review.
