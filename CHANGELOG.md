# Changelog

All notable changes to this repository are documented here. The format follows
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/), and every plugin follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Each repository release (`## [X.Y.Z]`, tagged `vX.Y.Z`) is also the release of the reusable
workflows and actions. Inside it, one `### <plugin> <version>` subsection per plugin that shipped,
tagged `<plugin>--v<version>`. A change you must act on starts with **Breaking:**.

## [Unreleased]

### Reusable workflows and actions

#### Added

- `deepseek-review.yml` and `actions/deepseek-review`: an AI review of a pull request's diff by
  DeepSeek, posted as one comment that later runs update. It reads the pull request over the
  GitHub API and checks nothing out, so no pull-request code runs; it skips, and passes, without
  the `DEEPSEEK_API_KEY` secret, for a fork's pull request, a draft or a closed one. Lockfiles and
  your `exclude` patterns are left out, the diff is capped at `max-diff-bytes` (100,000) and the
  answer at `max-tokens` (16,384), so a review costs a cent or two and at most about ten US cents;
  each comment shows the tokens it used. Mentions in the answer are quietened.
- `deploy-webhook.yml` and `actions/deploy-webhook`: when a pull request is merged into the
  production branch, POST to `DEPLOY_WEBHOOK_URL` with agent-deploy's `trigger-deploy.sh` (the
  same file, kept identical by a test): https only, a 3xx or 4xx fails the job, a busy platform is
  asked again, and the URL is never printed. With `docs-repository` and `DOCS_DISPATCH_TOKEN` it
  then sends `app-deployed`, which agent-docs-nextra's changelog answers.
- `strip-ai.yml`: runs `actions/strip-ai` after a merge into the production branch with a checkout
  that keeps no token; git gets the job's token from a credential helper in that step's
  environment.
- Every new reusable workflow takes `runs-on` (empty uses `CI_RUNNER`, then `ubuntu-latest`) and
  `timeout-minutes`, and every input is optional.

#### Changed

- `actions/strip-ai`: its README and header point at the reusable workflow and a checkout with
  `persist-credentials: false`. The action itself is unchanged.
- `scripts/workflow-policy.py` allows `issue_comment` in one place only: a template's
  `deepseek-review.yml` for `/ask-deepseek`, and only in its safe shape (`types: [created]`, a job
  that calls this repository's `deepseek-review.yml` with `contents: read` and
  `pull-requests: write`, an `if:` that requires a comment on a pull request by an OWNER, MEMBER or
  COLLABORATOR, and a called workflow that checks nothing out). ADR 0004 records why.
- `scripts/version-sync.mjs` accepts a caller pinned to the all-zero placeholder when its comment
  names the coming release, and asks for a changelog entry when any reusable workflow changes.
- `scripts/catalog.mjs` lists every workflow a plugin's setup installs as a component, with a docs
  page, in the README catalogs.

### agent-core 1.0.5

#### Changed

- `.claude/CI-RUNNERS.example.md` names the workflows the kit installs on each runner pool, and
  its budget test opens a throwaway pull request instead of a `workflow_dispatch` workflow, which
  the kit's CI policy does not use.
- The README catalog lists the CodeQL, dependency-review and workflows-lint workflows, each with a
  docs page.

### agent-ai-fastapi 1.1.0

#### Added

- Setup question `deepseek-review` (recommended no): `.github/workflows/deepseek-review.yml`, a
  DeepSeek review of each pull request with notes about a FastAPI service, leaving out Alembic
  revisions. Needs the `DEEPSEEK_API_KEY` secret. Held until a release pins it.
- A `.github/CODEOWNERS` starter, seeded once: CI, the guardrails, startup, settings and the
  database.

### agent-be-hono 1.1.0

#### Added

- Setup question `deepseek-review` (recommended no): `.github/workflows/deepseek-review.yml`, a
  DeepSeek review of each pull request with notes about a Hono + Drizzle API, leaving out
  drizzle-kit migrations and the exported spec. Needs the `DEEPSEEK_API_KEY` secret. Held until a
  release pins it.
- A `.github/CODEOWNERS` starter, seeded once: CI, the guardrails, startup, env and the database.

### agent-deploy 1.1.0

#### Added

- Setup question `deploy-on-merge` (recommended no): `.github/workflows/deploy.yml` deploys
  through your webhook when a pull request is merged into `prod`, one at a time and never
  cancelled. Needs the `DEPLOY_WEBHOOK_URL` secret; fails, rather than skipping, without it.
- Setup question `strip-ai` (recommended no): `.github/workflows/strip-ai.yml` strips the agent
  config from `prod` after each merge, merges back into `dev` and verifies both.
- Both callers are held until a release pins them.

### agent-docs-nextra 1.1.0

#### Added

- Setup question `deepseek-review` (recommended no): `.github/workflows/deepseek-review.yml`, a
  DeepSeek review of each pull request with notes about a Nextra site, leaving out the generated
  changelog and API reference. Needs the `DEEPSEEK_API_KEY` secret. Held until a release pins it.
- A `.github/CODEOWNERS` starter, seeded once: CI, the deploy target, the generators and the
  guardrails.

### agent-fe-nextjs 1.1.0

#### Added

- Setup question `deepseek-review` (recommended no): `.github/workflows/deepseek-review.yml`, a
  DeepSeek review of each pull request with notes about a Next.js app, leaving out the generated
  API client and the translation catalogues. Needs the `DEEPSEEK_API_KEY` secret. Held until a
  release pins it.

#### Changed

- The seeded `.github/CODEOWNERS` starter explains itself in the same words as the other stacks'
  and names the setup lock.

### agent-fe-nextjs-static 1.1.0

#### Added

- Setup question `react-doctor` (recommended no): `.github/workflows/react-doctor.yml` and
  `doctor.config.json`, advisory React Doctor comments and a commit status on pull requests.
- Setup question `deepseek-review` (recommended no): `.github/workflows/deepseek-review.yml`, a
  DeepSeek review of each pull request with notes about a static export. Needs the
  `DEEPSEEK_API_KEY` secret. Held until a release pins it.
- A `.github/CODEOWNERS` starter, seeded once: CI, the headers, the build config, the budgets and
  the guardrails.

## [1.1.0] - 2026-09-27

The guards now work on Linux, where they refused every command, and they see through RTK. The
guard scripts are out of the shell's reach, every stack gets a staged secret scan, and the Hono
stack runs its tests with CI's environment only. The reusable workflows and actions are unchanged
since 1.0.0, so the CI callers stay pinned to its commit.

### agent-core 1.0.4

#### Changed

- The README catalog names a long hook matcher in plain words (for example "file edits"), so the
  Kind column stays narrow. The exact matcher is still in `hooks/hooks.json`.

### agent-ai-fastapi 1.0.3

#### Changed

- The README catalog names a long hook matcher in plain words (for example "file edits"), so the
  Kind column stays narrow. The exact matcher is still in `hooks/hooks.json`.

### agent-be-hono 1.0.3

#### Changed

- The README catalog names a long hook matcher in plain words (for example "file edits"), so the
  Kind column stays narrow. The exact matcher is still in `hooks/hooks.json`.

### agent-docs-nextra 1.0.3

#### Changed

- The README catalog names a long hook matcher in plain words (for example "file edits"), so the
  Kind column stays narrow. The exact matcher is still in `hooks/hooks.json`.

### agent-fe-nextjs 1.0.3

#### Changed

- The README catalog names a long hook matcher in plain words (for example "file edits"), so the
  Kind column stays narrow. The exact matcher is still in `hooks/hooks.json`.

### agent-core 1.0.3

#### Fixed

- The README said deleting the lock and `.claude/agent-config.json` silences the hooks for
  everyone. The opt-in sticks on every machine that has seen it, so it now says how to turn the
  hooks off there.

### agent-core 1.0.2

#### Fixed

- On Linux, safety-check refused every command: the analyzer, over 128 KiB, reached python3 as
  one argument, and Linux starts no program with an argument over that size (`Argument list too
  long`), so the guard failed closed. python3 now reads the analyzer from a file descriptor. A
  python3 shim held to Linux's cap, in the tests and the probe harness, catches this on macOS too.
- safety-check now sees through RTK, an optional output-trimming CLI proxy: `rtk <command>` and
  `rtk proxy <command>` (also `rtk err`, `test` and `summary`) are judged as the command they run,
  and RTK's file readers (`read`, `smart`, `json`, `log`) as `cat`. Before, `rtk git push --force
  origin main`, `rtk proxy git push origin main`, `rtk git reset --hard HEAD~3` and
  `rtk git commit --no-verify` were let through. 37 new probe rows (29 block, 8 pass) prove the
  rule both ways. Every plugin's `scripts/lib.sh` carries the fix.
- The commands and agents that decide from `git`, `grep` or `gh` output (`review`, `commit`,
  `create-pr`, `resolve-pr-review`, `ship`, `promote`, `checkpoint`, `branch-cleanup`, `reviewer`,
  `security-guard`) say to run them as `rtk proxy <command>` where RTK is installed: its rewrite
  condenses a diff and prints a line for an empty one, so a review or an "is it empty" check could
  read the wrong thing.

#### Added

- `scripts/check/secrets.sh`: the staged secret scan as a script (`gitleaks git --staged` with the
  repo's `.gitleaks.toml`). It fails, never skips, when gitleaks or the config is missing, and warns
  but still scans when gitleaks is not the release CI pins. The stack plugins' `gates.list` run it.

#### Changed

- The working agreements add the reuse ladder: this codebase, the standard library, the
  framework's built-ins, a dependency already installed, and only then a new dependency or new
  code. The output-wrapper agreement and `OPERATIONS.example.md` name `rtk proxy <command>`.

### agent-ai-fastapi 1.0.2

#### Fixed

- The secret scan in `gates.list` ran `gitleaks git` without `--staged`, which reads committed
  history and never the staged changes. It now runs `scripts/check/secrets.sh`, as does
  `.pre-commit-config.yaml`. A repo set up earlier keeps its own `gates.list`; change that line by
  hand.
- `scripts/lib.sh` sees through RTK and runs on Linux (agent-core 1.0.2), and `ai-reviewer` reads
  the diff through `rtk proxy` where RTK is installed.

#### Changed

- Rule 2 of the `AGENTS.md` starter carries the reuse ladder.

### agent-be-hono 1.0.2

#### Added

- `scripts/check/ci-env.sh` runs a command with CI's test variables and nothing else: the
  env file the CI caller passes to the reusable gate (`.env.ci.example` by default), or a
  workflow's own `env:` blocks, plus `CI=true` and `BUN_OPTIONS=--no-env-file`, so neither a
  shell-exported variable nor a `.env`/`.env.test` file reaches the tests. It fails when that
  source is missing. `gates.list` runs the unit tests through it, and setup seeds
  `.env.ci.example`. A repo set up earlier keeps its own `gates.list`: to adopt it, change the
  `bun run test:coverage` line to `bash scripts/check/ci-env.sh bun run test:coverage` and commit a
  `.env.ci.example`.

#### Fixed

- `gates.list` runs `scripts/check/secrets.sh` for the staged secret scan (agent-core 1.0.2).
- `scripts/lib.sh` sees through RTK and runs on Linux (agent-core 1.0.2), and `reviewer` reads the
  diff through `rtk proxy` where RTK is installed.

#### Changed

- Rule 2 of the `AGENTS.md` starter carries the reuse ladder, and the testing rule runs coverage
  through `ci-env.sh`.

### agent-docs-nextra 1.0.2

#### Added

- `gates.list` runs `scripts/check/secrets.sh` on every commit: a docs repo had no staged secret
  scan before. A repo set up earlier keeps its own `gates.list`; add the line by hand.

#### Fixed

- `scripts/lib.sh` sees through RTK and runs on Linux (agent-core 1.0.2), and `security-guard` and
  `seo-validator` run their read commands through `rtk proxy` where RTK is installed.

### agent-fe-nextjs 1.0.2

#### Fixed

- `scripts/lib.sh` sees through RTK and runs on Linux (agent-core 1.0.2). `reviewer`, `i18n-guard`,
  `seo-validator` and the `react-doctor` triage read git output through `rtk proxy` where RTK is
  installed.
- `gates.list` runs `scripts/check/secrets.sh` for the staged secret scan (agent-core 1.0.2).

#### Changed

- Rule 2 of the `AGENTS.md` starter carries the reuse ladder.
- The README lists the skills to install by reference, impeccable and ui-animation (MIT), with
  their install command, license and pin; nothing of them is vendored. `PRODUCT.example.md` and
  `DESIGN.example.md` link the renamed skills section of the template's `SETUP.md`.

### agent-fe-nextjs-static 1.0.2

#### Fixed

- `review`, `launch-checklist`, `i18n-guard`, `security-guard` and `seo-validator` run git and
  curl through `rtk proxy` where RTK is installed.
- `gates.list` runs `scripts/check/secrets.sh` for the staged secret scan (agent-core 1.0.2).

#### Changed

- Rule 2 of the `AGENTS.md` starter carries the reuse ladder.
- The README recommends the ui-animation skill (MIT) by reference, with its install command,
  license and pin; nothing of it is vendored.

### agent-deploy 1.0.1

#### Fixed

- `promote-deploy` runs the check-run annotation read, the open-items `grep` and the migrations
  diff through `rtk proxy` where RTK is installed, so an empty list stays empty.

### agent-fe-threejs 1.0.1

#### Changed

- `docs/3d-skills.md` names a vetted pack, the Three.js Claude Skill Package (MIT), with an install
  pinned to its `v1.1.1` release, and corrects the pinning advice: `skills@1.7.0` checks out a tag
  or a branch, never a bare commit.

### agent-core 1.0.1

#### Fixed

- The settings template asks before an edit to `.claude/hooks/**` or `scripts/check/hook-probes.*`,
  as it already did for the unlock script and `scripts/env/`, so a change to a guard or to the
  probes that prove it always reaches you first.

#### Changed

- `docs/unlock.md`, the copy setup installs, says that the shell may not change the hooks, the
  probes or the unlock script, and lists the write routes the analyzer reads (`sed` and `awk`
  programs, inline code, paths handed over by `xargs`, `$( )` or `find -exec`).

### agent-ai-fastapi 1.0.1

#### Fixed

- The CI caller template pins the reusable quality gate to the v1.0.0 release commit, so setup
  installs it with the rest instead of holding it back.

### agent-be-hono 1.0.1

#### Fixed

- The CI caller template pins the reusable quality gate to the v1.0.0 release commit, so setup
  installs it with the rest instead of holding it back.

### agent-docs-nextra 1.0.1

#### Fixed

- The CI caller template pins the reusable quality gate to the v1.0.0 release commit, so setup
  installs it with the rest instead of holding it back.

### agent-fe-nextjs 1.0.1

#### Fixed

- The CI caller template pins the reusable quality gate to the v1.0.0 release commit, so setup
  installs it with the rest instead of holding it back.

### agent-fe-nextjs-static 1.0.1

#### Fixed

- The CI caller template pins the reusable quality gate to the v1.0.0 release commit, so setup
  installs it with the rest instead of holding it back.

## [1.0.0] - 2026-09-26

First release.

### Reusable workflows and actions

#### Added

- Five reusable quality gates, called from pull-request workflows only:
  `fe-nextjs-quality-gate.yml`, `fe-nextjs-static-quality-gate.yml`, `be-hono-quality-gate.yml`,
  `ai-fastapi-quality-gate.yml` and `docs-nextra-quality-gate.yml`, with every input optional.
- Composite actions `actions/quality-gate` (the gate's scripts) and `actions/strip-ai`.

### agent-core 1.0.0

#### Added

- Guards: `safety-check` (destructive commands, protected branches, gate skipping, `.env*`
  access, the unlock), `db-guard` (production SQL writes wait for `unlock db`) and `mcp-guard`
  (GitHub MCP writes onto protected branches). All fail closed and stay silent until a repo opts in.
- Feedback hooks: `post-edit`, `post-commit`, `prompt-intent`, `session-start`, and the
  `setup-check` notice.
- Commands: `help`, `setup`, `sync`, `plan`, `review`, `commit`, `create-pr`, `merge-pr`,
  `resolve-pr-review`, `ship`, `promote`, `branch-cleanup`, `rca`, `checkpoint`,
  `checkpoint-summary`, `learn-session`.
- Agents: `reviewer`, `security-guard`.
- The setup engine (`agent-setup`, `agent-sync`): dry run, one question at a time, create-only
  writes, four managed merges, a lock, and a deterministic `sync --check` with drift and
  double-wiring exit codes.
- Templates: permissions and the Bash sandbox, type and dead-code rules, check scripts, the unlock
  script and the `.env` helpers, `docs/unlock.md`, `.gitleaks.toml`, pull-request-only CodeQL,
  dependency review and workflow lint. A CI caller still pinned to the release placeholder is held
  back by setup (`warn`, and `held` in `sync --check`) instead of being installed.
- Commands that install files, commit, push, merge or post to GitHub are user-only
  (`disable-model-invocation: true`).

### agent-ai-fastapi 1.0.0

#### Added

- `migration-guard` hook, `ai-reviewer` agent, `setup` and `sync` commands.
- Templates: backend and Python rules, anti-patterns, pre-commit config, gate list, a
  pull-request-only CI caller, PR templates and the optional pipeline example.

### agent-be-hono 1.0.0

#### Added

- `migration-guard` hook, `reviewer` agent, `setup` and `sync` commands.
- Templates: Hono and Drizzle rules, anti-patterns, gate scripts (constants, coverage, migration
  drift, index coverage, module mocks), lint and test config, a pull-request-only CI caller.

### agent-deploy 1.0.0

#### Added

- `verify-deploy` (outside smoke test of a live deploy) and `promote-deploy` (fallback promotion
  when CI cannot run), both started only by the user; `setup` and `sync` commands.
- Templates: `scripts/deploy/verify-deploy.sh`, the optional `trigger-deploy.sh`, ask-first
  permissions.

### agent-docs-nextra 1.0.0

#### Added

- `generated-guard` hook, `security-guard` and `seo-validator` agents, `setup` and `sync`
  commands.
- Templates: the docs-content rule, anti-patterns, gate scripts, lint config, the env helper, a
  pull-request-only CI caller, and the optional changelog and deploy workflows.

### agent-fe-nextjs 1.0.0

#### Added

- `generated-guard` hook; `a11y-audit`, `review-soc`, `plan-fullstack`, `setup` and `sync`
  commands; `reviewer`, `i18n-guard` and `seo-validator` agents; `react-doctor` and `skeleton`
  skills. `react-doctor` is user-invoked, prefers the project's own CLI and asks before it downloads
  the pinned one; it keeps the vendor's Modified MIT License (`MIT AND
  LicenseRef-Million-Modified-MIT`).
- Templates: TypeScript and web rules, anti-patterns, standards, gate scripts, lint configs, the
  pre-commit hook, a pull-request-only CI caller, and six optional modules.

### agent-fe-nextjs-static 1.0.0

#### Added

- `review`, `a11y-audit`, `seo-audit`, `launch-checklist`, `setup` and `sync` commands;
  `seo-validator`, `security-guard` and `i18n-guard` agents.
- Templates: 12 static-site rules, 11 anti-patterns, 11 site checks that read the built site,
  `site.config.json`, lint and budget configs, `public/_headers`, a pull-request-only CI caller.

### agent-fe-threejs 1.0.0

#### Added

- `setup` and `sync` commands.
- Templates: the 3D scene rule, the glTF/GLB asset budget check with its config, and a guide to
  adding 3D skills by reference.

[Unreleased]: https://github.com/adhibuchori/agent-config-kit/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/adhibuchori/agent-config-kit/releases/tag/v1.1.0
[1.0.0]: https://github.com/adhibuchori/agent-config-kit/releases/tag/v1.0.0
