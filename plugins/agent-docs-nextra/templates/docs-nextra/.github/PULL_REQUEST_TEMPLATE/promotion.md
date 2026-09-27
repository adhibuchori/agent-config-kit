## Promotion: dev → prod

<!-- Filled in from `git log origin/prod..origin/dev` — do not hand-edit the commit
     list without re-checking it against that range. -->

### Commits Being Promoted

<!-- List each commit: short SHA — subject line. -->

`quality-gate.yaml` re-runs the full gate on this PR. That gate is the list; nothing it decides
is repeated here.

### Local Merge Verification

- [ ] Ran `git merge --no-commit --no-ff origin/dev` locally against `prod` before
      opening this PR
- Result: <!-- clean / conflicts found and how resolved / not run -->

## Post-Merge Checks

<!-- Delete the lines below that do not apply to this promotion before submitting. -->

- [ ] `changelog.yaml` ran for this merge, where the repo has it. A head commit carrying the
      skip-CI marker starts no workflow, and nothing reports the absence
- [ ] Production deployment succeeded — the Worker's newest deployment is dated after the merge
- [ ] The live site reflects the new content, checked on the pages that changed
- [ ] If this promotion carries a changelog revision: the generated page is live as well
