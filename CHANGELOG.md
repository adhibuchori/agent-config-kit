# Changelog

All notable changes to this repository are documented here. The format follows
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/), and every plugin follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Each repository release (`## [X.Y.Z]`, tagged `vX.Y.Z`) is also the release of the reusable
workflows and actions. Inside it, one `### <plugin> <version>` subsection per plugin that shipped,
tagged `<plugin>--v<version>`. A change you must act on starts with **Breaking:**.

## [Unreleased]

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

[Unreleased]: https://github.com/adhibuchori/agent-config-kit/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/adhibuchori/agent-config-kit/releases/tag/v1.0.0
