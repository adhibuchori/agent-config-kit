# quality-gate

Workflow · agent-ios-swiftui · `.github/workflows/quality-gate.yml` · installed by setup when you answer `ci-gate=yes` (recommended) · runs on every pull request into every branch · no secrets, no signing

## What it does

`.github/workflows/quality-gate.yml` runs agent-config-kit's `ios-swiftui-quality-gate.yml` reusable workflow on every pull request, pinned to one commit of the kit. A Linux job runs first: the `gates.list` lines that need no Mac (the String Catalog, error-code, suppression and privacy checks, folder shape, coverage policy, secrets and the AI config), a committed `.env` check, gitleaks over the pull request's commits, and SkillSpector when a skill, command, subagent or hook changed. Only when it passes does the macOS job run: the pinned Xcode 27.0, the whole `gates.list` (swift-format, SwiftLint and the per-file coverage of the logic package among them), the coverage floor, `xcodebuild test` on the newest iPhone simulator with zero build warnings (the accessibility audits included), the String Catalog against the keys the build extracted, Periphery, and the API client regenerated with no difference.

A check that cannot run fails the gate unless you pass `strict: false`. The jobs read the checkout and nothing else: `contents: read`, no secret, nothing signed, and the checkouts keep no token.

## When to reach for it

Setup writes it; after that it runs by itself on every pull request:

```text
/agent-ios-swiftui:setup --answer ci-gate=yes
```

Make **Quality Gate (ios-swiftui)** a required status check in your branch ruleset: it is the third
job, which passes only when both the Linux and the macOS job did. Every input is optional; set them
under `with:` in the caller, for example `scheme`, `xcode-version` or `runs-on`.

**Not for:** running the gates on your machine. `bash scripts/check/gates.sh` and the pre-commit
hook do that on the files you staged; `bash scripts/ios/app.sh test` runs the app's tests.

## Prerequisites

- The files setup installed, with the placeholders filled: `.periphery.yml` names your project and
  scheme, and the project's configurations are based on `Config/*.xcconfig`.
- Exactly one `.xcodeproj` at the repo root, both `Package.resolved` files committed (the build
  resolves only from them), and a committed `env-file` (default `.env.ci.example`), never real
  secrets.
- A caller pinned to a released commit. One that still holds the all-zero placeholder is held back
  by setup until a release pins it.

## Common questions

**Which runners does it use?**
The Linux job takes `CI_RUNNER_FAST`, then `CI_RUNNER`, then `ubuntu-latest`. The macOS job takes `CI_RUNNER_MACOS`, then GitHub's `xcode-27` runner, and fails when the runner's Xcode is not the pinned one. See `.claude/CI-RUNNERS.example.md`.

**What does it cost?**
On a public repository, nothing. On a private one, macOS minutes cost about ten times Linux ones, so a failure the Linux job finds never reaches the Mac.

**How do I take a newer gate?**
`/agent-ios-swiftui:sync` offers the new pin when a plugin release moves it. Nothing moves on its own.

## It's working if

- Every pull request shows **Quality Gate (ios-swiftui)**, and each job's log ends with the list of
  checks that passed, failed or did not run.
- A pull request that adds a build warning, an untranslated key or an untested file turns it red.

## Where it fits

The pull-request half of the gates the pre-commit hook runs. See [/agent-ios-swiftui:setup](setup.md)
and the [CI/CD at a glance](../../README.md#cicd-at-a-glance) table.
