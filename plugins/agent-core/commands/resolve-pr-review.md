---
description: Fetches a PR's review comments, triages them against the repo's rules, applies the ones the user accepts, re-runs the gates, then replies on each review thread and summarises on the PR.
argument-hint: "[PR number or URL] [reviewer]"
disable-model-invocation: true
---

# /agent-core:resolve-pr-review — PR Review Resolver

**Arguments:** $ARGUMENTS

## Step 1: Fetch

```bash
gh pr view {PR} --repo {OWNER/REPO} --json title,url,headRefName,additions,deletions,changedFiles
gh api "repos/{OWNER}/{REPO}/pulls/{PR}/comments" --paginate
gh api "repos/{OWNER}/{REPO}/pulls/{PR}/reviews" --paginate
```

With RTK installed, run the `gh api` calls as `rtk proxy gh api …`: its rewrite can shorten the
JSON, and every comment's `id` and body is needed. If a reviewer was named, filter to that user. If
there are no comments, say so and stop.

Fetch the review threads too; every inline comment belongs to one, and a thread already resolved
needs nothing:

```bash
gh api graphql -F owner={OWNER} -F repo={REPO} -F pr={PR} -f query='
query($owner: String!, $repo: String!, $pr: Int!) { repository(owner: $owner, name: $repo) {
  pullRequest(number: $pr) { reviewThreads(first: 100) { nodes {
    id isResolved path line comments(first: 1) { nodes { databaseId } } } } } } }'
```

Match each comment to its thread (the thread's first comment `databaseId` is the comment's `id`)
and skip the resolved ones.

## Step 2: Judge Each Against Project Rules

Cross-check every suggestion against `AGENTS.md` (where the repo has one) and `.claude/rules/`. A
reviewer bot does not know this repo's conventions and is regularly confident and wrong.

- Contradicts a rule → `⚠ Conflicts with Rule {N}` (or the rule file), recommend declining
- Supports a rule → `✓ Aligns with Rule {N}`
- Neither → `—`, judge on merit

## Step 3: Triage Table

| ID | File:Line | Reviewer | Type | Rule | Summary |
| :-- | :-- | :-- | :-- | :-- | :-- |

Type each one (bug, security, performance, refactor, style, test, other) and ask which to apply:
**All**, the IDs, or **None**, plus any notes on how. Order the accepted ones: security and bugs
first, then performance and architecture, then refactor and style. For more than a couple of
accepted items, show a fix plan in the `/agent-core:plan` shape and wait for approval before
changing anything.

## Step 4: Apply and Verify

Apply in priority order, then re-run the gates (`bash scripts/check/gates.sh`, or CLAUDE.md
§ Quality Gates): all must pass.

## Step 5: Reply On Each Thread, Then On The PR

Post the outcome in each inline comment's own thread (its `id` from Step 1), then summarise:

```bash
gh api -X POST "repos/{OWNER}/{REPO}/pulls/{PR}/comments/{COMMENT_ID}/replies" \
  -f body="<applied in <sha>, or declined and why>"
gh pr comment {PR} --repo {OWNER/REPO} --body "<what was applied, what was declined, and why>"
```

Reply even when nothing was applied. A declined suggestion needs a stated reason; silence reads as
an oversight and the next reviewer raises it again.

Then resolve each thread you answered, applied or declined with its reason, so the PR's readiness
check (`scripts/ops/pr-ready.sh`, which counts unresolved threads) and `/agent-core:merge-pr` can
pass; leave a thread open only when you asked the reviewer a question in it:

```bash
gh api graphql -F id={THREAD_ID} -f query='mutation($id: ID!) { resolveReviewThread(input: { threadId: $id }) { thread { isResolved } } }'
```

Commit the fixes with `/agent-core:commit` and push them before replying "applied in" with the
commit hash.
