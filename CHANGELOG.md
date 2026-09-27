# Changelog

All notable changes to this repository are documented here. The format follows
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/), and every plugin follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Each repository release (`## [X.Y.Z]`, tagged `vX.Y.Z`) is also the release of the reusable
workflows and actions. Inside it, one `### <plugin> <version>` subsection per plugin that shipped,
tagged `<plugin>--v<version>`. A change you must act on starts with **Breaking:**.

## [Unreleased]

### agent-core 1.1.1

#### Changed

- `CI-RUNNERS.example.md` says how to spend two free pools of minutes: the merge-blocking gate, the
  one job that must not die or stall, on a fast third-party pool (Blacksmith as the example), and
  every job that can fail without blocking anyone on GitHub's free minutes.

### agent-ai-fastapi 1.2.1

#### Fixed

- The CI callers are pinned to the v1.2.0 release commit, so setup installs them instead of
  holding them back.

### agent-be-hono 1.2.1

#### Fixed

- The CI callers are pinned to the v1.2.0 release commit, so setup installs them instead of
  holding them back.

### agent-deploy 1.1.2

#### Fixed

- The CI callers are pinned to the v1.2.0 release commit, so setup installs them instead of
  holding them back.

### agent-docs-nextra 1.1.2

#### Fixed

- The CI callers are pinned to the v1.2.0 release commit, so setup installs them instead of
  holding them back.

### agent-fe-nextjs 1.2.1

#### Fixed

- The CI callers are pinned to the v1.2.0 release commit, so setup installs them instead of
  holding them back.

### agent-fe-nextjs-static 1.1.2

#### Fixed

- The CI callers are pinned to the v1.2.0 release commit, so setup installs them instead of
  holding them back.

## [1.2.0] - 2026-09-28

The pull-request pipeline is complete, and the stacks gain the ported rule set. Three new reusable
workflows sit behind optional setup questions: a DeepSeek review of each pull request, a deploy on
merge through your webhook, and the strip of agent config from the production branch. Their
callers still hold the release placeholder, so setup keeps them back until the plugin releases
that pin them to this commit. The Hono, Next.js and FastAPI stacks gain the opt-in payload
contract, and every stack gains the missing rules, anti-patterns, checks and a CODEOWNERS starter.

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
  names the coming release (or, in the release pull request, the release being cut), and asks for
  a changelog entry when any reusable workflow changes.
- `scripts/catalog.mjs` lists every workflow a plugin's setup installs as a component, with a docs
  page, in the README catalogs.

### agent-core 1.1.0

#### Changed

- `.claude/CI-RUNNERS.example.md` names the workflows the kit installs on each runner pool, and
  its budget test opens a throwaway pull request instead of a `workflow_dispatch` workflow, which
  the kit's CI policy does not use.
- The README catalog lists the CodeQL, dependency-review and workflows-lint workflows, each with a
  docs page.
- `/agent-core:review` runs the installed i18n guard, SEO validator and accessibility audit on the
  parts of the diff they own, starts with the cheap scans (staged secrets, a real env file, eval and
  raw-HTML sinks, secret-shaped assignments), reports the gates it ran, and ends by offering the
  fixes.
- `/agent-core:resolve-pr-review` reads the review threads, skips resolved ones, shows a fix plan
  before a larger change, and resolves each thread it answered, so the readiness check can pass.
- `/agent-core:merge-pr` never uses `--auto`, and deletes an `internal/*` head only once the pull
  request reads `MERGED`. `/agent-core:create-pr` refuses a protected branch, runs the gates first,
  asks once for what is missing, and redrafts on request. `/agent-core:plan` adds UNKNOWNS, timed
  tasks, rated risks, phases past 50 tasks and per-stack layers.
- `/agent-core:promote` compares an Alembic head (not a count) and lists the browser pass it means.
- `DATABASE.example.md` says which query tools run the SQL they are given and when to widen the
  write guard; the working agreements add three lines (a green suite and an untested transport,
  another session's authorisation, the zsh array trap).

#### Added

- `/agent-core:check-fix`: runs the repo's gates, fixes each failure at its cause (format and lint
  twice, types, build, tests in CI's environment, schema and stack checks) and re-runs until green;
  it never silences a finding and never commits.
- The security guard checks web response headers where a repo renders pages: the header set, an
  unjustified `'unsafe-inline'` or `'unsafe-eval'`, a nonce CSP frozen into static config, raw HTML
  without a safety note, and the payload contract where a repo adopted it.
- `OPERATIONS.example.md` gains how the guards fail (closed, one deadline, the Linux argument cap)
  and why the shell cannot rewrite them, and sections on the unlock, the staged secret scan, server
  access with a break-glass order, and client IP behind a CDN or proxy.

### agent-ai-fastapi 1.2.0

#### Added

- Setup question `deepseek-review` (recommended no): `.github/workflows/deepseek-review.yml`, a
  DeepSeek review of each pull request with notes about a FastAPI service, leaving out Alembic
  revisions. Needs the `DEEPSEEK_API_KEY` secret. Held until a release pins it.
- A `.github/CODEOWNERS` starter, seeded once: CI, the guardrails, startup, settings and the
  database.
- The payload contract, an opt-in setup answer (`payload-encryption`): a Python implementation in
  `src/app/core/payload/` (the same envelope, AAD and freshness as the TypeScript stacks, key rings,
  the switch, and a plain ASGI middleware that replays the opened body and never invents a
  disconnect) with tests at 100% branch coverage, including the shared test vectors. It needs the
  `cryptography` package.

#### Changed

- The starter adds §P; the review checklist and the reviewer add input size caps, corpus changes,
  pipeline data integrity and the ways around the `Any` ban.

### agent-be-hono 1.2.0

#### Added

- Setup question `deepseek-review` (recommended no): `.github/workflows/deepseek-review.yml`, a
  DeepSeek review of each pull request with notes about a Hono + Drizzle API, leaving out
  drizzle-kit migrations and the exported spec. Needs the `DEEPSEEK_API_KEY` secret. Held until a
  release pins it.
- A `.github/CODEOWNERS` starter, seeded once: CI, the guardrails, startup, env and the database.
- The payload contract, an opt-in setup answer (`payload-encryption`): a reference implementation
  in `src/lib/payload/` (AES-256-GCM envelopes bound to method, route pattern, status and key id,
  a two-minute freshness window, pre-shared key rings with `_NEXT` rotation, browser key agreement,
  the committed strict/off switch refused in production) and a Hono middleware, with tests at 100%;
  the endpoint registry and `generate:endpoints`; `check:endpoints` (registry drift, reasons for
  every exemption, route literals, the committed switch, peer spec and policy parity) and
  `check:crypto-interop` (shared known-answer vectors and peers checked out beside the repo);
  `.claude/PAYLOAD-CONTRACT.md` and a rule that loads with the transport. Key material stays out
  of the repo.
- `check:openapi` and `spec:export`: the document the app declares builds, describes a route, and
  equals the committed `openapi.json`. `check:dockerfile`: the image builds what the gate validated.
- Anti-patterns: a cookie cache that outlives revocation, account endpoints the client cannot
  reach, passkey cancellation and user verification, a plugin list option that replaces its
  defaults, and a gateway cancel whose result is not the state.

#### Changed

- The starters add §P (the payload contract, where adopted), a transactional-email section and a
  known `zod-openapi` typing trap; the review checklist adds per-route guards; the Hono rule adds a
  switch for the public spec routes.

### agent-deploy 1.1.1

#### Added

- Setup question `deploy-on-merge` (recommended no): `.github/workflows/deploy.yml` deploys
  through your webhook when a pull request is merged into `prod`, one at a time and never
  cancelled. Needs the `DEPLOY_WEBHOOK_URL` secret; fails, rather than skipping, without it.
- Setup question `strip-ai` (recommended no): `.github/workflows/strip-ai.yml` strips the agent
  config from `prod` after each merge, merges back into `dev` and verifies both.
- Both callers are held until a release pins them.

#### Changed

- `/agent-deploy:promote-deploy` builds a static site before uploading it, confirms the content
  changed after, and walks the browser pass and a third-party sign-in on the live site.

### agent-docs-nextra 1.1.1

#### Added

- Setup question `deepseek-review` (recommended no): `.github/workflows/deepseek-review.yml`, a
  DeepSeek review of each pull request with notes about a Nextra site, leaving out the generated
  changelog and API reference. Needs the `DEEPSEEK_API_KEY` secret. Held until a release pins it.
- A `.github/CODEOWNERS` starter, seeded once: CI, the deploy target, the generators and the
  guardrails.

#### Changed

- The security guard checks third-party embeds and `javascript:`/`data:` URLs in MDX; the SEO
  validator gains a private-site mode; the starter says the reference generator needs the
  documented app checked out beside the docs repo.

### agent-fe-nextjs 1.2.0

#### Added

- Setup question `deepseek-review` (recommended no): `.github/workflows/deepseek-review.yml`, a
  DeepSeek review of each pull request with notes about a Next.js app, leaving out the generated
  API client and the translation catalogues. Needs the `DEEPSEEK_API_KEY` secret. Held until a
  release pins it.
- The payload contract, an opt-in setup answer (`payload-encryption`): the same reference cipher as
  the backend in `src/lib/payload/`, a browser transport (one agreed key per tab, a handshake, a
  refusal of plaintext successes on sealed routes) and a server bridge between the browser hop and
  the backend hop, with tests at 100%; the endpoint registry, `generate:endpoints`,
  `check:endpoints` (including raw `fetch` outside the transport and unregistered generated-client
  URLs) and `check:crypto-interop`; the contract document and its rule.
- `check:dockerfile`, and `check:skeleton-pairs` in the skeletons module: a skeleton a screen
  renders is measured in the harness or listed with a reason. `check:i18n` fails on a literal key a
  scoped translator uses that its namespace does not hold; `check:soc` flags a render loop in a
  component.
- Anti-patterns: a cookie cache that outlives revocation, gated account endpoints, passkey quirks,
  a prefixed `backdrop-filter` left alone by the CSS pipeline, and a cropper that letterboxes.

#### Changed

- The seeded `.github/CODEOWNERS` starter explains itself in the same words as the other stacks'
  and names the setup lock.
- The starters add §M (session and authorization boundary), §N (data surfaces) and §P (the payload
  contract), and SSOT §5.2, §5.4 and §5.5 (service-hook conventions, fixtures before the backend,
  three states). The reviewer checks them; the SEO validator gains an app-behind-sign-in mode;
  `plan-fullstack` carries authorization, states and fixtures; `serena-errors.md` starts with the
  known tool failures; the UI conventions add parity across sibling apps.

### agent-fe-nextjs-static 1.1.1

#### Added

- Setup question `react-doctor` (recommended no): `.github/workflows/react-doctor.yml` and
  `doctor.config.json`, advisory React Doctor comments and a commit status on pull requests.
- Setup question `deepseek-review` (recommended no): `.github/workflows/deepseek-review.yml`, a
  DeepSeek review of each pull request with notes about a static export. Needs the
  `DEEPSEEK_API_KEY` secret. Held until a release pins it.
- A `.github/CODEOWNERS` starter, seeded once: CI, the headers, the build config, the budgets and
  the guardrails.
- Anti-pattern: a prefixed `backdrop-filter` the CSS pipeline keeps while dropping the standard
  one.

### agent-fe-threejs 1.0.2

#### Changed

- The 3D rule warns about unscoped `npx` package names in skills and checks the renderer's React
  peer range before a React upgrade.

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

[Unreleased]: https://github.com/adhibuchori/agent-config-kit/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/adhibuchori/agent-config-kit/releases/tag/v1.2.0
[1.1.0]: https://github.com/adhibuchori/agent-config-kit/releases/tag/v1.1.0
[1.0.0]: https://github.com/adhibuchori/agent-config-kit/releases/tag/v1.0.0
