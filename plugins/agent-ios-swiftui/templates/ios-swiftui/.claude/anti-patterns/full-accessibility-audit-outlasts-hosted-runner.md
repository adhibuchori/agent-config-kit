# A full accessibility audit outlasts a hosted macOS runner

**Applies to:** the quality gate's macOS job, the UI tests (AGENTS.md Rule 24)
**Status:** Permanent (GitHub-hosted macOS runners, Xcode 27's audit)

## Symptom

Once every primary screen has its `performAccessibilityAudit` test, the gate's macOS job stops at
its timeout and is cancelled on every pull request. The tests that did run fail with "Contrast
failed" on plain body text that passes on a developer's Mac. Pull requests queue behind the cancelled
jobs for hours, because the account's macOS concurrency is spent waiting on them.

## Root cause

An audit takes one to three minutes per screen on a hosted runner, scrolled passes included: about
120 screens did not finish in 90 minutes. The runner is slow enough that the audit samples a screen
while its placeholder is still fading out, and reads that text against the wrong background. A
timeout also cancels the job before the checks that follow the tests could report.

## Fix

- Give CI its own scheme, `<App>CI`: the same app and UI test target, with only the quick,
  deterministic UI tests selected (`useTestSelectionWhitelist` in the scheme's test action). Pass it
  to the caller (`with: scheme: <App>CI`) and lower `timeout-minutes` to about 30.
- Run the whole audit on a developer's simulator, `bash scripts/ios/app.sh ui-test`, on the commit
  that ships, and on the screens a change touches before that.
- Add each new quick UI test to `<App>CI`'s selected tests as well.

## How to catch it

The macOS job's duration in the run list: a job that grows by minutes with each audit test added is
on its way here.

## Scope

Every app whose UI tests audit each screen and whose gate runs on a hosted macOS runner.
