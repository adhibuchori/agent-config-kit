# Changelog

All notable changes to this repository are documented here. The format follows
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/), and every plugin follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Each repository release (`## [X.Y.Z]`, tagged `vX.Y.Z`) is also the release of the reusable
workflows and actions. Inside it, one `### <plugin> <version>` subsection per plugin that shipped,
tagged `<plugin>--v<version>`. A change you must act on starts with **Breaking:**.

## [Unreleased]

## [1.5.2] - 2026-10-18

### Reusable workflows and actions

#### Fixed

- deploy-webhook retries from a fresh runner. Twice, one GitHub runner timed out on all four webhook
  attempts to a VPS that logged no dropped packet, firewall block or load, while a rerun on another
  runner was accepted at once: the runner's address did not reach the host. The deploy job now
  reports the webhook's outcome instead of failing, and a second job, `Deploy (fresh runner)`, runs
  the same step on a new runner when it failed. The docs dispatch goes out from whichever job
  deployed.

## [1.5.1] - 2026-10-18

The strip-ai caller is pinned to the v1.5.0 release commit and passes the optional push-key secret.

### agent-deploy 1.2.0

#### Added

- The strip-ai caller passes `push-key: ${{ secrets.STRIP_AI_PUSH_KEY }}`. Store a write deploy key's
  private key as `STRIP_AI_PUSH_KEY` and the strip and the back-merge push over SSH, so a ruleset
  that requires the quality gate on `prod` and `dev` can let deploy keys bypass it. Without the
  secret nothing changes.

#### Fixed

- The strip-ai caller is pinned to the v1.5.0 release commit.

## [1.5.0] - 2026-10-18

Two blockers met while syncing an app's repos to 1.4.1. safety-check refused agent-core's own
`agent-sync plan` and `check` in every repo already set up, since the engine reads its templates from
`~/.claude/plugins/`, a guard area; every plugin's `/sync` failed at its first step. And a repository
ruleset could not require the quality gate on `prod` and `dev` without stopping strip-ai's pushes,
because GitHub Actions cannot be a bypass actor there; deploy keys can.

### Reusable workflows and actions

#### Added

- strip-ai takes an optional `push-key` secret, the private key of a deploy key with write access.
  With it, the strip commit and the back-merge are pushed over SSH, trusting only the host keys
  GitHub publishes in its meta API, so a ruleset that requires status checks on both branches and
  lets deploy keys bypass it accepts them. The key lives in a private file for the one job and is
  removed afterwards. Without it nothing changes.

### agent-core 1.2.3

#### Fixed

- safety-check lets the setup engine read: `agent-sync check` and `plan`, `agent-setup questions`
  and `plan`, run from a plugin's `bin/` (under `.claude/plugins/`, or the running plugin's own), may
  name the plugin's templates. `apply` and `own` still refuse, since they rewrite the lock and the
  guard settings. A `./agent-sync` of the project's, one found through a `PATH` set or exported on
  the line, or a function or alias of that name, is not the engine. Twelve new probe rows cover both
  sides; the four that must pass fail on 1.2.2's library.
- setup and sync say what to do when safety-check refuses `apply` or `own` in a repo that is
  already set up: hand the user the exact line to run with `!`.

### agent-deploy 1.1.5

#### Fixed

- setup and sync say what to do when safety-check refuses `apply` or `own` in a repo that is
  already set up: hand the user the exact line to run with `!`.

### agent-be-hono 2.0.2

#### Fixed

- The hook library (`scripts/lib.sh`) is agent-core 1.2.3's: safety-check lets the setup engine's
  read-only modes name the plugin's templates, so this plugin's `/sync` drafts again in a repo that
  is already set up.
- setup and sync say what to do when safety-check refuses `apply` or `own` in a repo that is
  already set up: hand the user the exact line to run with `!`.

### agent-be-go 0.1.3

#### Fixed

- The hook library (`scripts/lib.sh`) is agent-core 1.2.3's: safety-check lets the setup engine's
  read-only modes name the plugin's templates, so this plugin's `/sync` drafts again in a repo that
  is already set up.
- setup and sync say what to do when safety-check refuses `apply` or `own` in a repo that is
  already set up: hand the user the exact line to run with `!`.

### agent-be-axum 0.1.3

#### Fixed

- The hook library (`scripts/lib.sh`) is agent-core 1.2.3's: safety-check lets the setup engine's
  read-only modes name the plugin's templates, so this plugin's `/sync` drafts again in a repo that
  is already set up.
- setup and sync say what to do when safety-check refuses `apply` or `own` in a repo that is
  already set up: hand the user the exact line to run with `!`.

### agent-ios-swiftui 1.0.2

#### Fixed

- The hook library (`scripts/lib.sh`) is agent-core 1.2.3's: safety-check lets the setup engine's
  read-only modes name the plugin's templates, so this plugin's `/sync` drafts again in a repo that
  is already set up.
- setup and sync say what to do when safety-check refuses `apply` or `own` in a repo that is
  already set up: hand the user the exact line to run with `!`.

### agent-ai-fastapi 1.3.2

#### Fixed

- The hook library (`scripts/lib.sh`) is agent-core 1.2.3's: safety-check lets the setup engine's
  read-only modes name the plugin's templates, so this plugin's `/sync` drafts again in a repo that
  is already set up.
- setup and sync say what to do when safety-check refuses `apply` or `own` in a repo that is
  already set up: hand the user the exact line to run with `!`.

### agent-docs-nextra 1.2.2

#### Fixed

- The hook library (`scripts/lib.sh`) is agent-core 1.2.3's: safety-check lets the setup engine's
  read-only modes name the plugin's templates, so this plugin's `/sync` drafts again in a repo that
  is already set up.
- setup and sync say what to do when safety-check refuses `apply` or `own` in a repo that is
  already set up: hand the user the exact line to run with `!`.

### agent-fe-nextjs 1.3.2

#### Fixed

- The hook library (`scripts/lib.sh`) is agent-core 1.2.3's: safety-check lets the setup engine's
  read-only modes name the plugin's templates, so this plugin's `/sync` drafts again in a repo that
  is already set up.
- setup and sync say what to do when safety-check refuses `apply` or `own` in a repo that is
  already set up: hand the user the exact line to run with `!`.

### agent-fe-nextjs-static 1.1.4

#### Fixed

- setup and sync say what to do when safety-check refuses `apply` or `own` in a repo that is
  already set up: hand the user the exact line to run with `!`.

### agent-fe-threejs 1.0.4

#### Fixed

- setup and sync say what to do when safety-check refuses `apply` or `own` in a repo that is
  already set up: hand the user the exact line to run with `!`.

## [1.4.1] - 2026-10-18

The ios-swiftui quality-gate caller is pinned to the v1.4.0 release commit, so setup and sync
install the gate that builds first and tests last.

### agent-ios-swiftui 1.0.1

#### Fixed

- The quality-gate caller is pinned to the v1.4.0 release commit: the macOS job runs
  `build-for-testing`, the String Catalog check, Periphery and the client drift check before
  `test-without-building`, so a failing or timed-out test no longer hides them.

## [1.4.0] - 2026-10-18

agent-ios-swiftui leaves 0.x: an app built with it reached production, and the lessons of that run
are in this release. The iOS gate builds first and tests last, so a failing or timed-out test no
longer hides what the build-dependent checks found.

### Reusable workflows and actions

#### Changed

- The iOS gate's macOS job runs `xcodebuild build-for-testing` (zero warnings, read from its own
  result bundle), then the String Catalog check against the build, Periphery and the API client
  drift check, and only then `xcodebuild test-without-building`. Before, a failing test skipped
  those checks, and a timeout cancelled the job before they ran: one app carried a stale catalog key
  and four unused properties for days behind a gate that never reached them.

### agent-ios-swiftui 1.0.0

#### Changed

- Stable: the plugin is no longer marked experimental. A rename, or a removed rule, check or
  setting, is now a major release.
- `scripts/ios/app.sh` takes `IOS_SIMULATOR_ID`, and otherwise picks an iPhone of the newest runtime
  that is not booted. A booted simulator is usually the one a developer is using: the unsigned test
  build replaced their signed app, whose Keychain then refused every write
  (`errSecMissingEntitlement`, -34018).
- The I4 finding for an extracted key no code uses says what usually causes it: a key written
  inside a ternary or a tuple, which the build does not extract. Mark it manual.
- The quality-gate caller and `.claude/rules/ios/testing.md` explain the CI scheme (`<App>CI`): the
  same app and UI test target with only the quick UI tests, once the accessibility audits outgrow
  the hosted macOS runner. The audits run on a developer's simulator. AGENTS.md Rule 24's row says
  so.

#### Added

- Anti-patterns: `full-accessibility-audit-outlasts-hosted-runner.md` (90 minutes on about 120
  screens, contrast sampled mid-fade), `periphery-reads-a-stale-index.md` (an incremental build
  keeps old index records; never cache `DerivedData` in CI) and
  `string-literal-in-ternary-is-not-extracted.md`.

### agent-core 1.2.2

#### Fixed

- `scripts/check/ai-config.sh` no longer reports a rule AGENTS.md defines as undefined. It piped
  `printf` into `grep -q` under `pipefail`: `grep -q` exits at its first match, `printf` dies of
  SIGPIPE, and the pipeline read as "not found", now and then, on a busy runner.
  `scripts/sync/workflows.sh` had the same pipe. Both read a here-string now, and a test refuses the
  pattern in every template script that sets `pipefail`.

#### Changed

- `/agent-core:help` no longer marks agent-ios-swiftui experimental.

## [1.3.5] - 2026-10-16

The ios-swiftui quality-gate caller is pinned to the v1.3.4 release commit, so setup and sync
install the simulator boot fix.

### agent-ios-swiftui 0.1.4

#### Fixed

- The quality-gate caller is pinned to the v1.3.4 release commit: the macOS job boots the simulator
  and waits for it before `xcodebuild test`, instead of failing on a cold simulator that cannot
  launch the UI test runner.

## [1.3.4] - 2026-10-16

### Reusable workflows and actions

#### Fixed

- The iOS gate boots the simulator and waits for it (`xcrun simctl bootstatus <udid> -b`) before
  `xcodebuild test`. Left to xcodebuild, a cold simulator on a busy macOS runner sometimes failed
  to launch the UI test runner ("Failed to launch", "operation never finished bootstrapping") after
  ten minutes, a runner fault that read as a failing test. One app hit it in 4 of its first 20 runs.
  A simulator that does not boot now fails the gate with that message, before the build.

## [1.3.3] - 2026-10-16

The callers whose reusable workflows 1.3.2 fixed are pinned to its release commit, so setup and
sync install those fixes. The Workflows Lint docs add a prerequisite: an Actions policy that allows
only selected actions must allow `docker://rhysd/actionlint:*` and `zizmorcore/zizmor-action@*`, or
every run ends in **Startup failure**.

### agent-ios-swiftui 0.1.3

#### Fixed

- The quality-gate caller is pinned to the v1.3.2 release commit: the static job no longer runs
  `swiftlint-static`, and the macOS job has gitleaks for `secrets.sh`.

### agent-deploy 1.1.4

#### Fixed

- The strip-ai caller is pinned to the v1.3.2 release commit, whose back-merge no longer stops on
  `index.lock` when the development branch edited a stripped file since the last strip.

## [1.3.2] - 2026-10-16

Fixes found by setting up a Hono API and a SwiftUI app from the kit, each proven by a test that fails
without it.

### Reusable workflows and actions

#### Fixed

- The iOS gate's static job no longer runs SwiftLint. `swiftlint-static` 0.65.1 aborts ("SourceKit is
  disabled by configuration") on any custom rule a file triggers, even in `swiftsyntax` mode, so a
  project with the template's `.swiftlint.yml` failed there on its first Swift file. SwiftLint runs in
  the macOS job with the rest of `gates.list`.
- Every job installs gitleaks, the iOS macOS job included: it runs the whole `gates.list`, whose
  `secrets.sh` line fails without gitleaks. Only the job that runs the pull-request checks scans the
  pull request's commits, as before.
- strip-ai's back-merge no longer fails on `index.lock` when the development branch edited a stripped
  file (`AGENTS.md`, `CLAUDE.md`) since the last strip. It piped `git diff` into a loop of
  `git checkout`, and `git diff` can still hold the index lock after printing, so on a runner the
  modify/delete conflicts it exists to settle stopped the job with the strip pushed and no
  back-merge. It reads each list first.

### agent-core 1.2.1

#### Fixed

- safety-check reads `bun <word>` as Bun's own command when the word is one of its subcommands
  (`test`, `build`, `x`, `exec` and a few more), not as the package.json script of that name. A
  `"test": "bun test src"` script looked like it called itself, so `bun test src`, `bun run test` and
  `bun run build` were refused as nesting too deep. `install`, `add` and the other commands that run
  lifecycle scripts are still followed into those scripts. Three new probes cover both sides.

### agent-be-hono 2.0.1

#### Fixed

- The hook library (`scripts/lib.sh`) is agent-core 1.2.1's, with its safety-check fix for Bun's
  own subcommands.
- The `lint` and `fl:ci` scripts pass `--ignore-path=.oxlintignore`, as fe-nextjs and docs-nextra
  do: oxlint reads only `.eslintignore` by itself, so `.oxlintignore` had no effect. It also leaves
  out the plugins' own `scripts/check/coverage-policy.mjs` and `scripts/check/folder-shape.mjs`, which
  `.oxfmtrc.json` already leaves out; `folder-shape.mjs` failed `max-lines` on a fresh setup.
- `.oxlintrc.json` puts the general `src/modules/*/**` override before the service and handler
  overrides, which now repeat its cross-module pattern. oxlint lets a later override replace a rule's
  options for the files both match, so services could import Hono and handlers could reach into
  another module's internals. `.claude/docs/lint-config.md` explains the order. `.oxlintrc.json` and
  `.oxlintignore` are seeded: an existing project copies both changes by hand.
- `scripts/check/ci-env.sh` runs the command with no variables when `.env.ci.example` is missing and no
  workflow names an env file, the way the quality gate reads it, instead of failing. A missing file a
  workflow names still fails.

### agent-be-go 0.1.2

#### Fixed

- The hook library (`scripts/lib.sh`) is agent-core 1.2.1's, with its safety-check fix for Bun's
  own subcommands.
- `scripts/check/ci-env.sh`: a missing `.env.ci.example` that no workflow names means no variables,
  as in agent-be-hono 2.0.1.

### agent-be-axum 0.1.2

#### Fixed

- The hook library (`scripts/lib.sh`) is agent-core 1.2.1's, with its safety-check fix for Bun's
  own subcommands.
- `scripts/check/ci-env.sh`: a missing `.env.ci.example` that no workflow names means no variables,
  as in agent-be-hono 2.0.1.

### agent-ios-swiftui 0.1.2

#### Fixed

- The hook library (`scripts/lib.sh`) is agent-core 1.2.1's, with its safety-check fix for Bun's
  own subcommands.
- `scripts/check/ci-env.sh`: a missing `.env.ci.example` that no workflow names means no variables,
  as in agent-be-hono 2.0.1.
- The quality-gate caller's comment says SwiftLint runs in the macOS job (see the reusable workflow
  fix above).

### agent-ai-fastapi 1.3.1

#### Fixed

- The hook library (`scripts/lib.sh`) is agent-core 1.2.1's, with its safety-check fix for Bun's
  own subcommands.

### agent-docs-nextra 1.2.1

#### Fixed

- The hook library (`scripts/lib.sh`) is agent-core 1.2.1's, with its safety-check fix for Bun's
  own subcommands.

### agent-fe-nextjs 1.3.1

#### Fixed

- The hook library (`scripts/lib.sh`) is agent-core 1.2.1's, with its safety-check fix for Bun's
  own subcommands.

## [1.3.1] - 2026-10-11

The quality-gate callers of the three stacks added in 1.3.0 are pinned to its release commit, so
setup now installs the CI gate with the rest.

### agent-be-go 0.1.1

#### Fixed

- The quality-gate caller is pinned to the v1.3.0 release commit, so setup installs it instead of
  holding it back.

### agent-be-axum 0.1.1

#### Fixed

- The quality-gate caller is pinned to the v1.3.0 release commit, so setup installs it instead of
  holding it back.

### agent-ios-swiftui 0.1.1

#### Fixed

- The quality-gate caller is pinned to the v1.3.0 release commit, so setup installs it instead of
  holding it back.

## [1.3.0] - 2026-10-11

Three experimental stack plugins join the marketplace at 0.1.0: agent-be-go (a Go HTTP service on
PostgreSQL), agent-be-axum (Rust and Axum on PostgreSQL) and agent-ios-swiftui (a SwiftUI app that
calls such an API). Each keeps the kit's four contracts: a line budget per file, one closed
error-code registry with an RFC 9457 body, no missing translation, and 100% coverage in its own
tool's metrics. Three reusable quality gates come with them. Their callers hold the release
placeholder, so setup keeps them back until the release that pins them.

In the same release, every stack mints its problem `type` from the error code under one https base
per API, payload refusals stop sending internal messages, the payload contract is ported to the Go
and Rust servers and the iOS client with a shared key-agreement vector, migration-guard learns an
append-only mode for hand-written migrations, and every plugin component now passes a SkillSpector
scan in CI. agent-be-hono is a major release: its `check:openapi` now requires the `Problem`
contract.

### Reusable workflows and actions

#### Added

- `be-go-quality-gate.yml`, `be-axum-quality-gate.yml` and `ios-swiftui-quality-gate.yml`
  (`workflow_call`, `contents: read`). The two backends start `postgres:18.6`, pinned by its
  multi-arch index digest, as a service on `127.0.0.1:5432` with trust auth; `database: false`
  starts none, for a repo that owns no schema. The iOS gate runs three jobs: the Linux-safe checks
  on Linux, the build and tests on macOS (`runs-on`, else `CI_RUNNER_MACOS`, else `xcode-27`, with
  the Xcode that `xcode-version` names through `DEVELOPER_DIR`) only after those passed, and a final
  job, **Quality Gate (ios-swiftui)**, that is the one check to require.
- `actions/quality-gate` knows the stacks `be-go`, `be-axum` and `ios-swiftui`
  (`scripts/stacks/*.sh`) and the inputs `phase`, `database`, `pgbouncer-tests`,
  `pgbouncer-max-prepared-statements`, `xcode-version` and `scheme`. For the backends:
  `db/roles.sql` before the tests, every migration from zero on an empty database (goose or sqlx),
  the `.sqlx` query cache against that schema (Rust), a foreign key without a leading index or an
  INVALID index fails, the migrations against the base branch and squawk over the new ones, the
  pool and server settings, govulncheck or `cargo deny`, the release build and the Docker build.
- `scripts/install-release.sh` and the pin table `scripts/tools.lock`: golangci-lint 2.14.0,
  squawk 2.68.0, cargo-llvm-cov 0.9.1, cargo-nextest 0.9.148, cargo-deny 0.20.2, SwiftLint 0.65.1
  (`swiftlint-static` on Linux) and Periphery 3.8.0, each refused unless its SHA-256 and the
  version it reports match; sqlx-cli 0.9.0, which ships no binary, is built with
  `cargo install --locked`.
- An optional PgBouncer check for be-go and be-axum (`pgbouncer-tests: true`):
  `scripts/pgbouncer.sh` starts `ghcr.io/cloudnative-pg/pgbouncer:1.26.0`, pinned by digest and
  version-checked, on `127.0.0.1:6432` in transaction mode and runs the repo's
  `scripts/check/pooler.sh` behind it.
- The coverage floor reads Go's cover profile (`coverage/coverage.out`, statements).

#### Changed

- The gate refuses more names in the env file, the ones that steer a Go, Rust, sqlx or Xcode
  toolchain: `GOFLAGS` and Go's other `GO…` names, `CGO_*`, `CARGO_*`, `RUSTUP_*`, `RUSTC*`,
  `RUSTFLAGS`, `RUSTDOCFLAGS`, `SQLX_*` and `DEVELOPER_DIR`. `GOOGLE_CLIENT_ID` and similar stay
  allowed.

### Repository checks

#### Added

- Self Test runs a **SkillSpector (plugins)** job: `scripts/skills-plugins.sh` lays every plugin
  out as a user's repo would hold it (commands and agents under `.claude/`, skills under
  `.claude/skills/`, hook scripts under `.claude/hooks/`) and runs the template's `skills.sh` with
  the template's baseline, unchanged. A scan that fails or reads a file only in part fails the job,
  as does a pull request that adds a line to the baseline. All eleven plugins pass with nothing at
  MEDIUM or above.
- `scripts/check-comment-style.mjs`, run by Self Test: the kit's JavaScript and TypeScript use
  `/** */` for a file or a declaration and `/* */` for other notes, and keep `//` for tool
  directives. `--fix` rewrites the rest; every existing comment was converted, with no change in
  behaviour.
- `tests/setup/conflicts.bats` derives the primary stacks from the plugins on disk and checks that
  every `conflictsWith` pair is mutual.

#### Changed

- `scripts/workflow-policy.py` fails a job that runs steps without `timeout-minutes`.
- `scripts/catalog.mjs` refuses `go run|generate|get|install`, `cargo run|install|add`,
  `swift run|package` and bare `xcodebuild` or `xcrun` in a template's `allow` list, and
  `cargo install`, `rustup`, `brew install` and `mint install` in hook and runtime scripts. A Go
  build constraint is never read as a file's description.
- `.github/gitleaks.toml` allows the `h1:` checksums in agent-be-go's `go.sum.starter`, that file
  only; gitleaks already skips `go.sum` in users' repos.

#### Fixed

- `scripts/catalog.mjs` matches `**` across folders. It matched within one folder, so the README
  called agent-be-hono's payload tests always installed when setup treats them as payload-only.
- `scripts/catalog.mjs` escapes a backslash before a pipe in a README table cell, so a backslash in
  a description can no longer undo the pipe's escape, and `scripts/version-sync.mjs` escapes every
  regular-expression metacharacter in a plugin name and version (CodeQL
  `js/incomplete-sanitization`). The generated READMEs do not change.

### agent-core 1.2.0

#### Added

- The `language` question also takes `go`, `rust` and `swift` (one choice), and setup reads
  `go.mod`, `Cargo.toml`, `Package.swift` and `*.xcodeproj` to suggest it. Each answer installs
  `.claude/rules/<language>/types.md` and `dead-code.md`, which load only while Claude edits that
  language. A lock written with `typescript`, `python` or `both` stays in sync.
- The agent `agent-core:spec-reviewer` checks a diff against the spec it implements (the linked
  issue, the approved plan, or a named spec file) and reports missing or partial requirements,
  unrequested behaviour and wrong implementations, each quoting its spec line.
- The hook setting `appendOnlyMigrationsDirs` (default empty) in `lib.sh`, documented in
  `.claude/agent-config.example.json`, `.claude/OPERATIONS.example.md` and the README's table.
  `hook-probes.sh` proves migration-guard's append-only mode, and generated-guard's Go and Rust
  markers, where the repo has the guard.
- post-edit gives feedback for `*.go` (golangci-lint fmt, then golangci-lint run on the package,
  capped at 20 s; `gofmt -w` and `go vet` without golangci-lint; `GOTOOLCHAIN=local GOPROXY=off
  GOFLAGS=-mod=readonly`), `*.rs` (rustfmt on stdin, written back only when it differs; `cargo
  clippy --locked --all-targets` from a root `Cargo.toml`, this file's lines, capped at 10 s;
  `RUSTUP_AUTO_INSTALL=0 CARGO_NET_OFFLINE=true SQLX_OFFLINE=true`), `*.swift` (`xcrun
  swift-format`, then swiftlint; a version mismatch says nothing), `*.xcstrings` (valid JSON, every
  key in every locale the catalog uses, state translated) and `*.pbxproj` (`plutil -lint`). A
  package-wide note stops after 40 lines.
- folder-shape.mjs knows Rust (`src/main.rs` and `src/lib.rs` are entrypoints, `mod.rs` does not
  count, `target/` is skipped) and Swift packages (`Packages/*/Sources` and `Tests`, or a root
  `Package.swift`: `XTests.swift` mirrors `X.swift`; `GeneratedSources/` is skipped). Go stays
  outside its roots, and `.claude/rules/common/folder-shape.md` says so.
- ai-config.sh check 5: every path in CLAUDE.md's "On-demand references" table (a cell that is one
  backticked path) exists, or its `*.example.*` sibling or a glob match does. A repo whose CLAUDE.md
  keeps rows for docs it never installed fails the gate until the row goes or the file is added.

#### Changed

- `/agent-core:review` runs two axes in separate subagents, started together: standards (the
  stack reviewer, else `agent-core:reviewer`, with security-guard and the specialists) and spec.
  The report keeps them in two sections, never merged or reranked, each with its worst finding;
  every finding cites a rule or a spec line; what a linter or gate enforces is skipped; neither
  subagent may run `/agent-core:review` again or start more subagents. The verdict is per axis.
- `/agent-core:ship` puts a spec-axis finding on the worklist as HIGH when the change misses or
  misimplements a requirement, and leaves behaviour the spec never asked for to the user.
- post-edit also passes on `path:line:` findings without a column (revive's file length).
- `CI-RUNNERS.example.md` adds `CI_RUNNER_MACOS` and explains the iOS gate's split.
- `help.md` lists the commands of the three new plugins.

#### Fixed

- SkillSpector reads `help`, `setup`, `review`, `security-guard` and the setup-check hook in full
  with no finding: they name `.env` in backticks, say "does not check who is calling" instead of
  "without checking", and show the workflow expression in a fenced block.

### agent-be-hono 2.0.0

#### Changed

- **Breaking:** `check:openapi` also checks the spec's `Problem` contract: `components.schemas.Problem`
  exists, `code` carries the `ERROR_CODES` enum inline (a `$ref` is not followed) and every code
  matches `^[A-Z][A-Z0-9_]*$`, `type` is `format: uri` with a valid `x-problem-type-base` (an
  absolute https URI ending in `/`, with no query or fragment), and `about:blank` is no default,
  const or enum value. A repo set up earlier fails its gate after sync until
  `src/lib/errors/problem.ts` publishes that contract (by hand, below). To defer, run
  `agent-sync own scripts/check/openapi.ts`: sync stops replacing the file, and
  `agent-sync own --undo scripts/check/openapi.ts` hands it back once `problem.ts` is ready.
- `createPayloadMiddleware` takes a required `problemTypeBase`, refuses to start with a base that
  cannot prefix a type, and puts the request id from `requestId()` in the refusal.
- `error-codes.md`, `hono.md`, `patterns.md`, the payload contract and its short rule, and
  `reviewer` describe the problem type: `PROBLEM_TYPE_BASE` plus the code, a fixed title per code, a
  registered code for 404, 405, `HTTPException` and 500, upstream problems minted again under this
  API's base, and the placeholder `https://example.invalid/problems/` refused in production.
- `scripts/check/ci-env.sh` recognises a caller of any `<stack>-quality-gate.yml` and refuses the
  same toolchain names as the gate (one regex, the same bytes as the gate's `QG_REFUSED_ENV`).
- `scripts/check/coverage-policy.mjs` (the same bytes in every stack) also checks a repo whose
  coverage runs from `scripts/check/coverage.sh`: the script hands its report to
  `coverage-per-file.mjs`, `gates.list` runs it through `ci-env.sh`, and every line of
  `scripts/check/coverage-exempt.txt` reads `<path or glob>  # composition root: <why>` or
  `# generated: <why>`. A repo with a bun, vitest or pyproject coverage config is checked as before.
- `CLAUDE.md.starter` marks the On-demand rows for files only one setup answer installs with
  "(with `<answer>=yes`)", so a fresh default setup passes agent-core's pointer check. Rule 26 in
  `AGENTS.md.starter` says blank lines and comments do not count, as `.oxlintrc.json` sets.
  Seeded files: existing repos are not changed.
- `conflictsWith` names agent-be-go, agent-be-axum and agent-ios-swiftui.
- Comments in the shipped scripts are block comments; no behaviour changes.

#### Added

- migration-guard's append-only mode for hand-written migrations (`appendOnlyMigrationsDirs`): a
  new migration, or one only the work branch has, stays editable; a write to a file any
  `protectedBranches` branch already holds (locally or as `origin/<branch>`) is refused, and so is
  one where git cannot answer. ADR 0007. Drizzle folders behave as before.
- `src/lib/payload/refusal.ts` (seeded with `payload-encryption=yes`) builds the refusal:
  `{ type: <base><CODE>, title, status, code, requestId? }`, one title per code, and
  `checkProblemTypeBase`; it imports nothing from Hono. Its test is `__tests__/refusal.test.ts`.
- The shared payload vectors carry a key-agreement answer: `agreements` (a fixed server JWK and
  client scalar, the ECDH shared bytes, the HKDF-SHA-256 session key and an envelope sealed under
  it) and `pointRejects` (a point off the curve, 64 bytes without the prefix, a compressed point).
  The existing keys are unchanged. `check:crypto-interop` runs them through the synced helper
  `scripts/lib/payload-agreement.ts`: WebCrypto derives the shared bytes from both sides and the key
  with HKDF, and `src/lib/payload/ecdh.ts` must open the envelope from either side and refuse every
  bad point with `ENVELOPE_MALFORMED`.

#### Fixed

- The payload middleware's default refusal sent the internal error message as `detail`, which
  names route patterns and server state; it now sends the code and no `detail`.
- A sealed response carries `Vary: x-payload-epk, x-payload-kid`, so a shared cache never serves
  one caller's envelope to another.
- The payload contract's error table says what both implementations do: an unknown version or a
  missing field is `ENVELOPE_REQUIRED`, not `ENVELOPE_MALFORMED`. Each code documents its title and
  status.
- `check:endpoints` and `generate:endpoints` refuse a `payload.config.json` `encryption` that is
  neither `strict` nor `off`; a typo such as `stirct` used to read as strict. An absent value still
  means strict.
- `deriveSessionKey` refuses a peer key that is not the 65-byte uncompressed point. Node and Bun
  imported a compressed point, which the Go, Rust and Swift ports refuse.
- A Serena `replace_in_files` that reaches a migrations folder says "reaches migrations
  (migrationsDirs or appendOnlyMigrationsDirs)".

#### By hand

Seeded files never sync. Where `payload-encryption=yes`:

1. Copy `src/lib/payload/refusal.ts` and `src/lib/payload/__tests__/refusal.test.ts` from the
   template.
2. In `src/middlewares/payload.middleware.ts`, take the template's version, or drop `detail` from
   the default refusal, build it with `payloadRefusal(base, status, error.code, requestIdOf(c))`,
   add `problemTypeBase` to the options (checked with `checkProblemTypeBase`), and
   `headers.append('vary', 'x-payload-epk, x-payload-kid')` where the response is sealed. Update its
   test the same way.
3. In `src/app.ts`, pass `problemTypeBase: PROBLEM_TYPE_BASE` to `createPayloadMiddleware`.
4. Copy the length and prefix check from the template's `src/lib/payload/ecdh.ts` (and its test),
   or `check:crypto-interop` reports `point reject compressed point: accepted`.
5. `SSOT.md` "Error Contract" and `AGENTS.md` §C: the new shape and the base (the starters show the
   wording).

In every repo, the project-owned `src/lib/errors/problem.ts`:

1. `export const PROBLEM_TYPE_BASE = 'https://api.example.com/problems/';` with your own domain,
   set once and never changed. Refuse to start in production while its host ends in `.invalid`.
2. Mint every body's `type` as `${PROBLEM_TYPE_BASE}${code}`, give each code a fixed `title`, and
   map 404, 405, every `HTTPException` and unknown 500s to registered codes; a relayed upstream
   problem keeps its code and status under this base.
3. Make the registered `Problem` schema carry `type` as `format: uri` with
   `x-problem-type-base: PROBLEM_TYPE_BASE`, `code` with the `ERROR_CODES` enum inline, both
   `required`, and no `about:blank` default; then `bun run spec:export`, run `check:openapi`, and
   copy `openapi.json` to every frontend.

### agent-fe-nextjs 1.3.0

#### Added

- `check:error-codes` compares the spec's `x-problem-type-base` with a `PROBLEM_TYPE_BASE` export
  in `src/lib/errors/problem-key.ts`. It fails when the spec's base is malformed, when the spec
  publishes a base and the export is missing or differs, and when the export exists but the spec
  publishes none; a spec with neither passes and says that problems resolve by code. Action is
  needed only once your API publishes a base.
- The shared payload vectors carry the key-agreement answer, and `check:crypto-interop` derives it
  from both sides through `scripts/lib/payload-agreement.ts`. A repo that holds the browser client
  (`src/lib/payload/client.ts`) is the client side, so the bad-point vectors are the server's to
  refuse and a repo that adopted the contract earlier keeps passing. The template's `ecdh.ts`
  refuses a compressed point, as every server does.
- generated-guard also refuses a write to an existing Go file whose header has a whole
  `// Code generated ... DO NOT EDIT.` line before the package clause, and to a Rust file with
  `@generated` in a comment among its first five lines, wherever the file lives. Such a file that a
  hand edit used to reach is now refused; `"generatedPaths": []` no longer switches this part off
  (disable the plugin for that). A folder-wide `replace_in_files` is still judged by
  `generatedPaths` only.

#### Changed

- `error-codes.md` (identical to agent-be-hono's) gives the order a frontend resolves a problem in:
  the base plus a known code gets its message; an absent or `about:blank` type falls back to the
  code; anything else is unknown. `reviewer` flags a mapping that ignores `type`, and the payload
  contract asks the proxy route to send `Vary` on what it seals for the browser.
- generated-guard's refusal says the API contract is exported by the service that owns it or
  copied from it.
- `scripts/check/coverage-policy.mjs`: the shared copy, as in agent-be-hono.
- `CLAUDE.md.starter` marks the On-demand rows for files only one setup answer installs, as in
  agent-be-hono.
- `conflictsWith` names the three new stacks. `scripts/lib.sh` copy updated.
- Comments in the shipped scripts are block comments; no behaviour changes.

#### Fixed

- The payload contract's error table (`ENVELOPE_REQUIRED` for an unknown version or a missing
  field), and `check:endpoints` refuses a misspelled `encryption` switch, as in agent-be-hono.
- SkillSpector reads the `react-doctor` and `skeleton` skills in full: their paths and the
  CLI-choosing line moved to `references/cli.md` and `references/files.md`, and the rule-explain
  command sits in a fenced block. What the skills tell Claude is unchanged.

#### By hand

- Seeded files: `AGENTS.md` Rule 37 (resolve a problem by its type; the starter shows the
  wording); the comment on `ENVELOPE_REQUIRED` and `ENVELOPE_MALFORMED` in
  `src/lib/payload/errors.ts` (wording only).
- Project-owned `src/lib/errors/problem-key.ts`: export `PROBLEM_TYPE_BASE`, equal to the spec's
  `x-problem-type-base`, and resolve a body by its type before the code:

  ```ts
  export const PROBLEM_TYPE_BASE = 'https://api.example.com/problems/';
  export function problemCodeOf(body: unknown): string | undefined {
    if (typeof body !== 'object' || body === null) return undefined;
    const code: unknown = Reflect.get(body, 'code');
    const raw: unknown = Reflect.get(body, 'type');
    const type = typeof raw === 'string' ? raw : 'about:blank';
    if (typeof code !== 'string') return undefined;
    return type === `${PROBLEM_TYPE_BASE}${code}` || type === 'about:blank' ? code : undefined;
  }
  ```

  A proxy route that seals for the browser also sets `Vary: x-payload-epk, x-payload-kid`, and a
  refusal it raises itself sends the contract's body.

### agent-ai-fastapi 1.3.0

#### Added

- migration-guard's append-only mode, as in agent-be-hono; Alembic folders behave as before.

#### Changed

- `PayloadMiddleware` takes a required `problem_type_base` keyword and refuses to start with a base
  that cannot prefix a type. The seeded tests assert whole refusal bodies and stay at 100% branch
  coverage.
- `fastapi.md` and `testing.md` describe the shape `{type, title, status, code}` with `code`
  required and `type == PROBLEM_TYPE_BASE + code`; `ai-reviewer` flags `about:blank`, a hand-built
  type, a per-occurrence title, `instance` set to a resource id, and a changed base.
- `scripts/check/payload-vectors.json` gains the `agreements` and `pointRejects` sections every
  stack shares. The Python service is a server caller with no key agreement, so its seeded tests
  read only the AES vectors and pass unchanged.
- `scripts/check/coverage-policy.mjs`: the shared copy, as in agent-be-hono.
- `CLAUDE.md.starter` marks the On-demand rows for files only one setup answer installs.
- `conflictsWith` names the three new stacks. `scripts/lib.sh` copy updated.

#### Fixed

- The payload middleware's refusal sent the internal error message as `detail` and no `type`
  (which reads as `about:blank`); it now sends `{ type: <base><CODE>, title, status, code }` with
  one title per code.
- A sealed response carries `Vary: x-payload-epk, x-payload-kid`.
- The payload contract's error table, as in agent-be-hono.

#### By hand

- Seeded files, where `payload-encryption=yes`: take the template's
  `src/app/core/payload/middleware.py` and `tests/unit/core/payload/test_middleware.py`, or drop
  `"detail": str(error)` from `_refuse`, add `type` and the per-code titles, add the
  `problem_type_base` keyword, and add the `vary` pair to the sealed response's headers. Pass
  `problem_type_base=PROBLEM_TYPE_BASE` where `main.py` adds the middleware.
- Seeded starters: `AGENTS.md` Rule 10 (the shape is `{type, title, status, code}` plus an
  optional client-safe `detail`) and the widget recipe (a per-type `title`, no
  `instance=widget_id`: `instance` names an occurrence, RFC 9457 section 3.1.5); `SSOT.md` "Error
  contract".
- Project-owned `src/app/core/errors/problems.py`: define `PROBLEM_TYPE_BASE` (your own https base,
  set once, refused in production while its host ends in `.invalid`), mint
  `type = PROBLEM_TYPE_BASE + code` for every body, make `code` required (404, 422 and unhandled
  500s get registered codes), keep `title` fixed per code, and leave `instance` out unless it names
  the occurrence.

### agent-docs-nextra 1.2.0

#### Added

- generated-guard recognises the Go and Rust generated-code markers, as in agent-fe-nextjs, and its
  refusal names where the API contract comes from.

#### Changed

- `CLAUDE.md.starter` marks the On-demand rows for files only one setup answer installs.
- `conflictsWith` names the three new stacks. `scripts/lib.sh` copy updated.

### agent-fe-nextjs-static 1.1.3

#### Changed

- `conflictsWith` names the three new stacks.
- Comments in the shipped check scripts are block comments; no behaviour changes.

### agent-fe-threejs 1.0.3

#### Fixed

- `setup` says the budget check runs "without a permission prompt", a wording SkillSpector no
  longer reads as an agent acting unasked. Comments in the shipped check script are block comments.

### agent-deploy 1.1.3

#### Fixed

- `sync` says a missing `ask` rule lets a network script run "with no permission prompt", a wording
  SkillSpector no longer reads as an agent acting unasked.

### agent-be-go 0.1.0

#### Added

- A new, experimental stack plugin for Go HTTP services on PostgreSQL: `net/http` with a server
  oapi-codegen v2.8.0 generates from `api/openapi.yaml` (spec first), pgx v5 and sqlc for queries,
  goose for migrations, golangci-lint v2.14.0. Rule numbers, layout and setup questions may still
  change before 1.0.0.
- Hooks: `migration-guard` (the shared script; setup seeds `appendOnlyMigrationsDirs:
  ["db/migrations"]`) and `generated-guard` (setup seeds `generatedPaths` for `api/openapi.json`,
  `internal/httpapi/api.gen.go` and `internal/postgres/db`).
- Commands `/agent-be-go:setup` and `/agent-be-go:sync`; the `agent-be-go:reviewer` subagent (the
  standards axis of `/agent-core:review`); the skills `api-endpoint` (contract first, one tracer
  bullet per behaviour) and `db-migration` (expand, backfill, contract).
- What setup installs: a 32-rule `AGENTS.md` index (Rules 28 to 32 apply with
  `payload-encryption=yes`) and a 0.5 KB `CLAUDE.md` starter; path-scoped rules for the Go service,
  PostgreSQL (byte-identical with agent-be-axum's), testing, error codes and coverage; 17
  anti-patterns (7 for Go, 10 PostgreSQL ones shared with agent-be-axum); a service skeleton with
  every hand-written file at 100% statement coverage: the closed error-code registry (`apperr.Code`
  with unexported fields, a go/ast registry test, `reassign`), the one RFC 9457 writer with `type` =
  `apperr.TypeBase` + code and a production refusal of the `example.invalid` placeholder, the router
  with spec validation (kin-openapi) and problem answers for 404 and 405, the handler-size test (15
  lines), the server with all four timeouts, an explicit pool that refuses timeouts in the
  connection string and `describe_exec`, and tests that migrate the test database themselves and
  run as the service's role; `db/roles.sql` (migrator, service and read-only agent roles, timeouts
  on the role); the gate scripts (`lint.sh`, `generated.sh`, `migrations.sh`, `endpoints.sh`,
  `coverage.sh`, `pooler.sh`, the payload registry check) with `gates.list`, `.githooks/pre-commit`,
  `.golangci.yml`, `sqlc.yaml`, `.squawk.toml`, `go.mod` and `go.sum` starters (or a by-hand snippet
  with the `tool` lines), PR templates, CODEOWNERS, an optional DeepSeek review caller, and the
  caller of `be-go-quality-gate.yml`, held back until the release that pins it.
- Setup questions: `migrations`, `ci-gate`, `deepseek-review`, `pr-templates`, `analytics`,
  `serena-workspace` and `payload-encryption` (recommended no). Yes installs the payload contract in
  Go, standard library only (`crypto/ecdh`, `crypto/hkdf`, `crypto/aes` and `crypto/cipher`):
  `internal/payload` (AES-256-GCM envelopes bound to method, route and status; P-256 key agreement
  with browsers and apps through `x-payload-epk`; `kid:base64key` rings with `PAYLOAD_KEY_NEXT`; the
  strict/off switch; the registry generated from `api/openapi.json`), the `net/http` middleware and
  its buffering writer in `internal/httpapi` (outside the kin-openapi validator, matched through a
  private `ServeMux`, `Vary: x-payload-epk, x-payload-kid` on every sealed answer), the five
  `ENVELOPE_*` codes in `internal/apperr/payload_codes.go`, `config.LoadPayload`,
  `payload.config.json` (the handshake named `GetPayloadHandshake`, as oapi-codegen exports it),
  `scripts/generate/payload-server-key.mjs`, the shared contract, short rule and vectors, and
  `.claude/rules/backend/go-payload.md`. The seeded tests reach 100% of statements and open the
  shared vectors, the key agreement included; `boundary_test.go` keeps `internal/payload` behind
  `internal/httpapi` and `cmd/`.
- `scripts/{lib,generate,check}/payload-registry.mjs`, the same bytes in the three new stacks (plain
  Node, no dependencies), are installed in every repo. The generator writes the registry from the
  spec and `payload.config.json` in the layout gofmt keeps. The check fails on a switch other than
  `strict`, registry drift, a stale exemption or one without a reason, a spec whose `Problem.code`
  lacks an `ENVELOPE_*` code, a handshake that is missing, not a GET or not exempted `none`, and
  spec or exemption drift from a checked-out peer of any stack. Without `payload.config.json` it
  says the contract is not adopted and passes.
- `apperr.Error.WithStatus` answers an error with another 4xx or 5xx status than its code's, for
  `ENVELOPE_MALFORMED` as a 500 when a service cannot seal its own answer.

#### By hand, once per repo

- Replace `example.com/service` with the module path in `go.mod`, `.golangci.yml` and the seeded Go
  files.
- Set `apperr.TypeBase` and `x-problem-type-base` in `api/openapi.yaml` to this API's own https
  base before the first release; production refuses to start with the placeholder.
- `git config core.hooksPath .githooks` once per clone.
- With `payload-encryption=yes`: add the five codes to `Registered()` and to `Problem.code`, add
  `GET /api/payload/handshake` and exempt it (and the health probe) as `none` when browsers or apps
  call the service, wire `sealBodies` into `NewRouter` and the edge into `main`, and regenerate. The
  gates stay red until then, on purpose. The rule file shows each step.

### agent-be-axum 0.1.0

#### Added

- A new, experimental stack plugin for Rust and Axum services on PostgreSQL (axum 0.8, tower-http
  0.7, sqlx 0.9, utoipa 6). Names and rules may still change before 1.0.0.
- Hooks: migration-guard keeps hand-written sqlx migrations append-only once a protected branch has
  them (`appendOnlyMigrationsDirs`), and generated-guard refuses hand edits to the sqlx query cache
  and the exported `openapi.json` (`generatedPaths`). Both are the shared copies.
- Commands `/agent-be-axum:setup` and `/agent-be-axum:sync`. Setup asks seven questions
  (`migrations`, `ci-gate`, `deepseek-review`, `pr-templates`, `analytics`, `serena-workspace`,
  `payload-encryption`) and installs no `package.json`; a new repo gets `Cargo.toml` from a starter,
  an existing one a by-hand block (`_kit/snippets/cargo.toml`: the `[lints]` tables and
  `[profile.release]`).
- The agent `agent-be-axum:reviewer`, the standards axis of a review. The skills `api-endpoint`
  (code first: path constant, annotated handler, one red request test, green, regenerated spec) and
  `db-migration` (expand, backfill, contract; the no-transaction marker; the FK index in the same
  file; the offline query cache).
- The template: a 34-rule `AGENTS.md` index (Rules 30 to 34 apply with `payload-encryption=yes`)
  with a `CLAUDE.md` starter of about 0.5 KB; rules for the service layout, PostgreSQL, testing,
  error codes and Rust coverage; 20 anti-patterns (10 for Rust, 10 PostgreSQL ones shared with
  agent-be-go); clippy, rustfmt, cargo-deny, nextest and toolchain config; `.cargo/config.toml`
  with `[build] warnings = "deny"` and `[env] SQLX_OFFLINE = "true"`; a service skeleton whose error
  module (RFC 9457, `type` = `PROBLEM_TYPE_BASE` + code, the startup check), `ValidJson` extractor,
  layers, pool and tests pass every gate at 100% of lines and functions per file; `openapi.json`
  with `x-problem-type-base` and the inline code enum; the gate scripts `rustfmt.sh`,
  `cargo-policy.sh`, `rust-source.mjs` (LINES, HANDLERS, ROUTES, LAYERS, SQL, ALLOW),
  `migrations.sh`, `coverage.sh`, `pooler.sh` and the payload registry check with `gates.list` and
  `.githooks/pre-commit`; a pull-request-only caller of `be-axum-quality-gate.yml` (held back until
  the release that pins it), an optional DeepSeek review, PR templates and a CODEOWNERS starter.
- `payload-encryption=yes` installs the payload contract: `src/payload/` (AES-256-GCM envelopes
  bound to method, route and status; P-256 key agreement for public clients such as an iOS app;
  pre-shared key rings with `_NEXT` rotation for server callers; the `strict`/`off` switch, `off`
  refused in production; the generated endpoint registry) and `src/routes/payload.rs` with
  `payload_layer.rs` (a `route_layer` that finds the route through `MatchedPath`, opens a sealed
  request before `ValidJson`, seals the answer with `Vary: x-payload-epk, x-payload-kid`, and the
  `GET /api/payload/handshake` handler). The seeded tests reach 100% of lines and functions and
  include the shared vectors and their key-agreement answer. It also installs
  `payload.config.json`, `scripts/check/payload-vectors.json`,
  `scripts/generate/payload-server-key.mjs`, the contract document and two rules
  (`.claude/rules/common/payload-contract.md`, and `.claude/rules/backend/payload.md` for the Rust
  specifics). RustCrypto only (p256 0.14.0, aes-gcm 0.11.1, sha2 0.11.0, base64 0.22.1): no C
  library, no build script, and no duplicate version under `cargo deny check`.
- The shared `payload-registry.mjs` scripts, installed in every repo, write the registry in the
  layout rustfmt keeps; `rust-source.mjs` LAYERS refuses `crate::payload` outside `src/routes/`,
  `src/lib.rs` and `src/payload/`.
- The error seed has a crate-private `WireCode` trait: `problem()` is generic over it, so
  `PayloadCode` uses the one problem writer without becoming a variant of `ErrorCode`. The
  `problems` layer keeps any error body whose media type ends in `+json`, so a sealed 4xx answer is
  never replaced by a plaintext problem.

#### By hand, once per repo

- With `payload-encryption=yes`, wire the module in as `src/payload/mod.rs` lists: `cargo add` the
  four crates at those versions; the four `PAYLOAD_*` fields in `Config`; the `PAYLOAD_HANDSHAKE`
  path; `mod payload;`, `payload::routes()` and `payload::document` in `routes/mod.rs`;
  `routes::payload::seal` in `lib.rs` after every route is merged; `check_payload_settings` in
  `main.rs`. A module nothing declares is not compiled, so the skeleton stays green until then; the
  registry gate stays red until `openapi.json` lists the five `ENVELOPE_*` codes and the handshake.

### agent-ios-swiftui 0.1.0

#### Added

- A new, experimental plugin for a SwiftUI iOS app on Xcode 27 and Swift 6.4, on top of agent-core:
  rules, reviewers and checks. Names, rules and checks may still change before 1.0.0.
- Hook: `generated-guard` (the shared script) refuses hand edits to the generated API client, the
  copied OpenAPI spec and the generated payload registry (`generatedPaths`).
- Commands: `/agent-ios-swiftui:setup` and `/agent-ios-swiftui:sync` (user-only), and
  `/agent-ios-swiftui:a11y-audit`, which runs the accessibility audit UI tests on a simulator and
  reports each issue. Agents: `reviewer` (the standards axis) and `i18n-guard`. Skills:
  `swiftui-screen` (one screen as a tracer bullet, model first) and `openapi-client-update`.
- Setup installs a 33-rule `AGENTS.md` index (Rules 29 to 33 apply with `payload-encryption=yes`)
  and a short `CLAUDE.md`; rules for the app target, the logic package, strings, tests, error codes
  and coverage; 12 anti-patterns; `Config/*.xcconfig` (Swift 6, approachable concurrency, MainActor
  default isolation, warnings as errors, `SWIFT_PACKAGE_NAME = appcore`); a strict `.swiftlint.yml`
  pinned to SwiftLint 0.65.1 with custom rules for views, strings, routes, problem codes, tokens and
  suppressions; `.swift-format`; `.periphery.yml`; a `Packages/AppCore` starter with `AppProblem` (an
  RFC 9457 problem the generated client decodes into through `typeOverrides`, read member by member,
  resolved by `type` = base + code) and its tests at 100%; a privacy manifest;
  `.githooks/pre-commit`; a pull-request-only caller of `ios-swiftui-quality-gate.yml` (held until
  the release pins it), an optional DeepSeek review, PR templates and a CODEOWNERS starter. Setup
  questions: `ci-gate`, `deepseek-review`, `pr-templates`, `serena-workspace`, `min-ios`, `locales`,
  `analytics`, `payload-encryption`.
- Check scripts: `lint-suppressions.sh` (a reason on every `swiftlint:disable`, no nested config, no
  `swift-format-ignore`, no lowering `@diagnose`), `xcode-settings.sh` (settings in
  `Config/*.xcconfig`, no `SWIFT_*` key in the project file, ATS on, no secret in an xcconfig),
  `package-graph.sh` (layers, a test target per library target, `exact:` pins, both
  `Package.resolved` files agree, plugins and macros only by decision), `i18n-catalog.mjs` (every
  locale translated, no stale key, and with `--stringsdata` the catalog against the build),
  `error-codes.sh` (the app's codes and problem-type base equal the spec's, each code has its
  message), `privacy-manifest.sh` (python3 plistlib, so it runs on Linux), `coverage.sh` (`swift
  test` + `llvm-cov export -format=lcov` + `coverage-per-file.mjs`, never xccov) and the shared
  payload registry check; named scripts `scripts/ios/app.sh` (simulator build and tests by udid, no
  signing, zero warnings from the result bundle) and `scripts/ios/api-client.sh` (the generator's
  command plugin, `--check` for drift).
- `payload-encryption=yes` (yes when the backend seals bodies) installs the app's half of the
  payload contract, seeded: `Payload*.swift` in `Packages/AppCore/Sources/APIClient` (envelope and
  AAD, AES-256-GCM, ECDH P-256 with HKDF-SHA-256 and the browser hop's label
  `payload-envelope/v1/browser`, a `PayloadSession` actor with one handshake in flight and the
  agreed key in memory only, never pinned and dropped after `ENVELOPE_REJECTED`, a
  `PayloadMiddleware` placed last in the client's list, and `AppProblem(failure:)`, the one error
  mapper for payload failures) with Swift Testing tests at 100% of lines and functions, and
  `payload.config.json` (`language: swift`, the handshake exempted `none`; its operation id is
  copied from the backend's spec, `GetPayloadHandshake` for an agent-be-go backend). Every payload
  type is `internal`; a Release build seals even when the handshake or the committed switch says
  `off`; `PayloadSession(serverURL:)` sends through a URLSession with no URLCache.
- The generated client is `internal` to `APIClient`, behind hand-written `package` calls: with
  `accessModifier: package` the generator's `package import` lines are flagged as unused under
  Swift 6.4 for every component section the spec leaves empty, and the package treats warnings as
  errors.

## [1.2.1] - 2026-09-28

The CI callers added in 1.2.0 are pinned to its release commit, so setup now installs the review,
deploy and strip workflows. The runner guide places jobs by what must not die and shows how to
spend two free pools of minutes, with Blacksmith as the example fast pool. The payload rule names
the `ENVELOPE_*` refusal codes.

### agent-be-hono 1.2.2

#### Fixed

- The payload rule names the refusal codes the contract and the code use, `ENVELOPE_*`; it said
  `PAYLOAD_*`.

### agent-fe-nextjs 1.2.2

#### Fixed

- The payload rule names the refusal codes the contract and the code use, `ENVELOPE_*`; it said
  `PAYLOAD_*`.

### agent-ai-fastapi 1.2.2

#### Fixed

- The payload rule names the refusal codes the contract and the code use, `ENVELOPE_*`; it said
  `PAYLOAD_*`.

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

[Unreleased]: https://github.com/adhibuchori/agent-config-kit/compare/v1.3.5...HEAD
[1.3.5]: https://github.com/adhibuchori/agent-config-kit/releases/tag/v1.3.5
[1.3.4]: https://github.com/adhibuchori/agent-config-kit/releases/tag/v1.3.4
[1.3.3]: https://github.com/adhibuchori/agent-config-kit/releases/tag/v1.3.3
[1.3.2]: https://github.com/adhibuchori/agent-config-kit/releases/tag/v1.3.2
[1.3.1]: https://github.com/adhibuchori/agent-config-kit/releases/tag/v1.3.1
[1.3.0]: https://github.com/adhibuchori/agent-config-kit/releases/tag/v1.3.0
[1.2.1]: https://github.com/adhibuchori/agent-config-kit/releases/tag/v1.2.1
[1.2.0]: https://github.com/adhibuchori/agent-config-kit/releases/tag/v1.2.0
[1.1.0]: https://github.com/adhibuchori/agent-config-kit/releases/tag/v1.1.0
[1.0.0]: https://github.com/adhibuchori/agent-config-kit/releases/tag/v1.0.0
