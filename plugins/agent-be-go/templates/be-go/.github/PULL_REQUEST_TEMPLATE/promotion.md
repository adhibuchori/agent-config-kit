## Promotion: dev → prod

<!-- Filled in from `git log origin/prod..origin/dev`: do not hand-edit the commit
     list without re-checking it against that range. -->

### Commits Being Promoted

<!-- List each commit: short SHA — subject line. -->

### Local Merge Verification

- [ ] Ran `git merge --no-commit --no-ff origin/dev` locally against `prod` before
      opening this PR
- Result: <!-- clean / conflicts found and how resolved / not run -->

## Expected Diff Noise

If this repo strips the AI configuration from `prod` on every merge, this PR's diff will look
larger than the commit list above: every stripped path (`.claude/`, `AGENTS.md`, `CLAUDE.md` and
the rest) reappears as "new" on every promotion. This is expected noise, not scope creep.

`quality-gate.yml` runs on this PR too. What it decides is not repeated here.

## Downstream

If a client (`<client-repo>`) generates from this repo's `api/openapi.json`:

- [ ] If the spec moved, the client has regenerated against it, and **that** release does not go
      out ahead of this one

## Post-Merge Checks

- [ ] Production migrations ran before the deploy, through a direct connection (not the pooler),
      and the count prod was behind is stated here rather than assumed to be zero
- [ ] A migration that waited on a lock and timed out was retried, not skipped
- [ ] The deploy is confirmed on the platform: a green deploy workflow run proves only that the
      webhook accepted it
- [ ] `GET /api/health` on the deployed instance returns `{"status":"ok"}`
