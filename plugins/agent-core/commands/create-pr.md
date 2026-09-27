---
description: Detects the branch context, drafts a PR title and a description from the repo's PR template, confirms both with the user, then pushes the branch and opens the PR into dev.
disable-model-invocation: true
---

# /agent-core:create-pr — Create Pull Request

## Step 0: Detect Context

```bash
git fetch origin
git branch --show-current
git log origin/dev..HEAD --oneline
git diff origin/dev...HEAD --stat
```

The base branch is **`dev`**, never `main`: work goes `internal/{scope}` → `dev` → `prod` (the
branch model in CLAUDE.md § Branching). A promotion into `prod` is `/agent-core:promote`'s job. A
repo with no `dev` branch on the remote uses its default branch as the base; say so.

## Step 1: Collect What Is Missing

Ticket ID (optional), one-sentence feature description, any breaking change or migration note.

## Step 2: Draft

**Title:** `type: [TICKET-ID] Description` in CLAUDE.md § Commit Format, under 70 characters.

**Description:** the repo's PR template, filled in: `.github/PULL_REQUEST_TEMPLATE/dev.md` when it
exists, else `.github/pull_request_template.md`; with neither, a Summary and a How to Verify
section. Write the Summary and How to Verify sections; tick or answer each checklist line; delete the
conditional blocks this change does not touch. Add nothing the quality gate already decides: the CI
workflow is the list, and a second copy of it here is the part that goes stale.

## Step 3: Confirm

Show title and body. Ask whether they are correct before creating.

## Step 4: Create

Push every commit first, in one push: each push to a branch with an open PR starts a fresh CI run.

```bash
git push -u origin "$(git branch --show-current)"
gh pr create --title "<title>" --body-file <filled template> --base dev
```

Output the PR URL.
