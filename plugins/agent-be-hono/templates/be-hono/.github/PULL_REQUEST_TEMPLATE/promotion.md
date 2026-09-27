## Promotion: dev → prod

<!-- Filled in from `git log origin/prod..origin/dev` — do not hand-edit the commit
     list without re-checking it against that range. -->

### Commits Being Promoted

<!-- List each commit: short SHA — subject line. -->

### Local Merge Verification

- [ ] Ran `git merge --no-commit --no-ff origin/dev` locally against `prod` before
      opening this PR
- Result: <!-- clean / conflicts found and how resolved / not run -->

## Expected Diff Noise

If this repo strips the AI configuration from `prod` on every merge, this PR's diff will look
larger than the commit list above: every stripped path (`.claude/`, `AGENTS.md`, `CLAUDE.md`,
`SSOT.md` and the rest) reappears as "new" on every single promotion. This is expected noise,
not scope creep.

`quality-gate.yml` runs on this PR too. What it decides is not repeated here.

## Downstream

If a frontend (`<frontend-repo>`) generates its API client from this repo's `openapi.json`:

- [ ] If the spec moved, the frontend has regenerated against it, and **that** promotion does not
      go out ahead of this one

## Post-Merge Checks

- [ ] Production migrations ran before the deploy (the migration step of `/agent-core:promote`), and the
      count prod was behind is stated here rather than assumed to be zero
- [ ] The deploy is confirmed on the platform: a green deploy workflow run proves only that the
      webhook accepted it
- [ ] `GET /health` on the deployed instance returns `{ "status": "ok", ... }`
