## Promotion: dev → prod

<!-- Filled in from `git log origin/prod..origin/dev`: do not hand-edit the commit list without
     re-checking it against that range. -->

### Commits Being Promoted

<!-- List each commit: short SHA, subject line. -->

### Local Merge Verification

- [ ] Ran `git merge --no-commit --no-ff origin/dev` locally against `prod` before opening this PR
- Result: <!-- clean / conflicts found and how resolved / not run -->

`quality-gate.yml` runs on this PR too. What it decides is not repeated here.

## The release

- [ ] The version and build number are raised in the project, once
- [ ] The backend this build calls is already in production, with every error code
      `ProblemCode` lists (an older backend shows newer screens the generic message)
- [ ] `App/PrivacyInfo.xcprivacy` matches what this release collects and the APIs it uses
- [ ] The archive was built on a Mac with the Xcode version CI pins

## Post-Release Checks

- [ ] The build reached TestFlight and was installed on a real device
- [ ] Sign-in, the main flow and one error path were exercised on that device
