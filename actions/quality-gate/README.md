# quality-gate action

The steps behind the eight reusable quality-gate workflows in
[`.github/workflows/`](../../.github/workflows/). A stack plugin's `/<plugin>:setup` installs a small
caller of one of them in your repository; this page is the reference for what that caller runs.

The gate's rule is that a pre-commit hook runs your repository's gates on staged files, and the
pull request runs them again on everything, plus the checks that need a pull request. Your
`scripts/check/gates.list` is the list: the gate does not keep a second copy of it.

## What it runs

In this order, per stack. **Gates** is `bash scripts/check/gates.sh`, which runs every line of your
`scripts/check/gates.list` (agent-core's setup installs `gates.sh`; your stack plugin's setup wrote
the list).

| Check | fe-nextjs | fe-nextjs-static | be-hono | ai-fastapi | docs-nextra |
| --- | --- | --- | --- | --- | --- |
| Install exactly the lockfile (no dependency lifecycle scripts) | yes | yes | yes | `uv sync --frozen` | yes |
| Generate the API client (an orval config and a `generate:api` script) | yes | | | | |
| Gates (`scripts/check/gates.list`) | yes | yes | yes | yes | yes |
| Coverage floor (`coverage-threshold`) | 100 | off (0) | 100 | 100 (coverage.py) | |
| Migration drift, index coverage (`scripts/check/migrations.sh`, `index-coverage.sh`) | | | yes | | |
| Runtime hardening (`src/app.ts`, `src/db/client/index.ts`) | | | yes | | |
| No `.env` file committed (only `.env*.example`) | yes | yes | yes | yes | yes |
| Added lines: `eval`/`new Function`, `dangerouslySetInnerHTML`, `javascript:`/`data:` URLs | yes | yes | yes | | yes |
| gitleaks over the pull request's commits (`.gitleaks.toml` when present) | yes | yes | yes | yes | yes |
| Audit (`scripts/check/audit.ts` with bun; `pip-audit` when it is a dev dependency) | yes | yes | yes | yes | yes |
| SkillSpector, when a skill, command, subagent or hook changed | yes | yes | yes | yes | yes |
| OpenAPI spec drift (a `spec:export` script) | | | yes | | |
| Generated pages that still hold TODO placeholders (a warning) | | | | | yes |
| Production build | `build` | `build` | `build` | `docker build` (a Dockerfile) | `build` |
| Built-site audit (`scripts/check/site-audit.mjs --env production`) | | yes | | | |
| No source maps in the output | `.next/static` | `out/_next/static`, `.next/static` | `dist` | | `.next/static`, `out/_next/static` |
| Integration tests (`integration-tests: true`) | | | | yes | |

The diff scans read only the lines the pull request adds, in JavaScript and TypeScript files. They
skip tests, `.d.ts` files, `scripts/check/`, `.github/` and `content/`, which may quote the very
patterns they refuse.

The Go, Rust and Swift stacks, in the same order. ios-swiftui runs in two jobs (see
[iOS: a Linux job, then a macOS job](#ios-a-linux-job-then-a-macos-job)):

| Check | be-go | be-axum | ios-swiftui |
| --- | --- | --- | --- |
| Toolchain | Go from `go.mod`; `GOTOOLCHAIN=local`, `GOFLAGS=-mod=readonly` | `rust-toolchain.toml`, then `RUSTUP_AUTO_INSTALL=0` | Xcode `xcode-version` through `DEVELOPER_DIR` (build) |
| Pinned tools ([`tools.lock`](scripts/tools.lock)) | golangci-lint, squawk | cargo-llvm-cov, cargo-nextest, cargo-deny, squawk, sqlx-cli | SwiftLint (static and build), Periphery (build) |
| Install exactly the lock | `go mod download`, `go mod verify` | `cargo fetch --locked` | |
| Roles (`db/roles.sql`, before the tests) | yes | yes | |
| Gates (`scripts/check/gates.list`) | yes | yes | static: the Linux-safe lines; build: every line |
| Coverage floor (`coverage-threshold`) | 100, statements (`coverage/coverage.out`) | 100, lines and functions (`coverage/lcov.info`) | 100, lines and functions (build) |
| Every migration from zero, on an empty database | `goose up` (`db/migrations`) | `sqlx migrate run` (`migrations`) | |
| Query cache against that schema | | `cargo sqlx prepare --check` | |
| Catalog: a foreign key without a leading index, an INVALID index | yes | yes | |
| PgBouncer check (`pgbouncer-tests: true`) | `scripts/check/pooler.sh` | `scripts/check/pooler.sh` | |
| Migrations against the base branch (`scripts/check/migrations.sh --base`) | yes | yes | |
| squawk over the migrations the pull request adds | yes (the `-- +goose Down` part is not linted) | yes | |
| Runtime settings | pool (`internal/postgres`), server (`cmd/api`, `internal/httpapi`) | pool (`src/platform/db.rs`) | |
| No `.env` file committed; gitleaks over the pull request's commits | yes | yes | static |
| Audit | `go tool govulncheck` (text mode) | `cargo deny --locked check` | |
| SkillSpector, when a skill, command, subagent or hook changed | yes | yes | static |
| OpenAPI spec drift | `gates.list` regenerates it | `src/bin/openapi.rs` writes `openapi.json` | API client regenerated, no diff (build) |
| Build and test | `go build -trimpath ./...` | `cargo build --locked --release` | `xcodebuild test`, newest iPhone simulator, zero warnings (build) |
| String catalog, from the build's `.stringsdata` (I3, I4) | | | `i18n-catalog.mjs --stringsdata` (build) |
| Dead code | | | `periphery scan --strict` with `.periphery.yml` (build) |
| Docker build (a `Dockerfile`) | yes | yes | |

`database: false` is for a repo that owns no schema: the workflow starts no PostgreSQL, and every
check about the schema (roles, migrations, catalog, PgBouncer, `migrations.sh`, squawk, the pool
settings) says so instead of running.

**Strict.** Every check passes, fails, or is listed as a check that did not run: no gitleaks build
for the runner, no coverage report, no `gates.list`. With `strict: true` (the default), a check that
did not run fails the gate, because a gate that quietly skipped its secret scan looks the same as
one that passed it. The summary at the end of the log lists both.

## PostgreSQL (be-go, be-axum)

The reusable workflow starts `postgres:18.6`, pinned by its multi-arch index digest, as a service
on `127.0.0.1:5432` with trust auth: the container lives for one job, so no password exists
anywhere and `.env.ci.example` holds none. Its URLs name the role and database only, for example
`TEST_DATABASE_URL=postgres://app_rw@127.0.0.1:5432/app_test?sslmode=disable`.

- `db/roles.sql`, when the repository has one, runs once as the superuser `postgres` with
  `psql -v ON_ERROR_STOP=1` before `gates.list`, so the roles and databases the tests use exist. It
  needs no psql variable.
- The migrations run on a database of their own, `qg_migrations`, created empty, as the superuser
  and on a direct connection: a migrator holds a session-level advisory lock, so it never goes
  through a pooler. The catalog queries ([`scripts/sql/`](scripts/sql/)) read that database.
- `QG_PG_ADMIN_URL` points the gate's own steps at another server when you run `gate.sh` by hand.

### PgBouncer check

With `pgbouncer-tests: true`, after the catalog checks, the gate starts
`ghcr.io/cloudnative-pg/pgbouncer:1.26.0` (pinned by digest; the gate refuses it unless
`pgbouncer --version` says 1.26.0) on `127.0.0.1:6432`, in transaction mode, in front of the
gate's PostgreSQL, and runs your `scripts/check/pooler.sh` while it is up. The configuration is
written fresh each run: any database name forwards to `127.0.0.1:5432`, `pool_mode = transaction`,
`default_pool_size = 2` (fewer server connections than client tasks), `max_prepared_statements`
from `pgbouncer-max-prepared-statements` (default 200; 0 copies a pooler that disables it), trust
auth for every non-superuser login role, and no `ignore_startup_parameters`, as on a fresh install.
Your env file names the URL the tests use through it, `TEST_POOLER_DATABASE_URL` (port 6432). The
container is removed on every path, and its last 40 log lines print when something fails. No
docker, or no `pooler.sh`, is a check that did not run.

## iOS: a Linux job, then a macOS job

`ios-swiftui-quality-gate.yml` runs three jobs, and the one to require is the last, **Quality Gate
(ios-swiftui)**:

1. **static**, on Linux (`phase: static`): every `gates.list` line whose command is, or starts
   with, a Linux-safe entry (the `node` and `bash` checks that read files:
   `i18n-catalog.mjs`, `folder-shape.mjs`, `coverage-policy.mjs`, `payload-registry.mjs`,
   `lint-suppressions.sh`, `error-codes.sh`, `privacy-manifest.sh`, `secrets.sh`, `ai-config.sh`),
   exactly as written, then the `.env` check, gitleaks and SkillSpector. Every other line is
   listed as running in the macOS job, SwiftLint's among them: the pinned `swiftlint-static` aborts
   ("SourceKit is disabled by configuration") on any custom rule a file triggers, even in
   `swiftsyntax` mode.
2. **build**, on macOS, only when static passed (`phase: build`): the Xcode release must be
   `xcode-version`, then the whole `gates.list`, the coverage floor, `xcodebuild test` (unit and UI
   tests, `CODE_SIGNING_ALLOWED=NO`, `-onlyUsePackageVersionsFromResolvedFile`) on the first iPhone
   of the newest iOS runtime, zero build warnings as `xcresulttool` counts them, the string catalog
   checks that need the build, Periphery over the index that build wrote, and the API client
   regenerated with `swift-openapi-generator`'s command plugin with no diff.
3. **gate** passes only when both did. A job skipped because the one before it failed does not
   block a merge on its own, so this one is the required check.

The macOS job runs on `runs-on`, else the caller's `CI_RUNNER_MACOS`, else `xcode-27`. The
default, `phase: all`, runs both phases in one go, for a Mac by hand.

## Pinned tools

[`scripts/tools.lock`](scripts/tools.lock) pins one release of each tool the Go, Rust and Swift
gates install, per platform, with the SHA-256 the release itself publishes;
[`scripts/install-release.sh`](scripts/install-release.sh) downloads it, refuses it on any other
checksum, and refuses it again unless the binary reports that release. sqlx-cli has no official
binary, so it is built with `cargo install --locked` at its exact version. A runner with no row for
its platform installs nothing, and the check that needs the tool records that it did not run.

## Inputs

| Input | Default | What it does |
| --- | --- | --- |
| `stack` | (required) | `fe-nextjs`, `fe-nextjs-static`, `be-hono`, `be-go`, `be-axum`, `ai-fastapi`, `ios-swiftui` or `docs-nextra` |
| `base-ref` | (required) | The branch the pull request merges into; `dev` resolves to `origin/dev`. The reusable workflows pass `github.base_ref` |
| `package-manager` | `auto` | `auto` reads the lockfile (`bun.lock`, `pnpm-lock.yaml`, `yarn.lock`, `package-lock.json`); or `bun`, `pnpm`, `npm`, `yarn`. ai-fastapi always uses uv; be-go, be-axum and ios-swiftui take `auto` only |
| `coverage-threshold` | stack default | The floor, 0 to 100 (empty: 100, or 0 for fe-nextjs-static and docs-nextra), read from the report your tests wrote: `lcov.info`, `coverage-summary.json`, `coverage-final.json` or Go's `coverage.out` under `coverage/` (or where `gates.sh` put it), or `.coverage` for Python. Lines, statements, functions and branches each count when the report measured them. `0` turns it off; your test runner's own thresholds still apply |
| `env-file` | `.env.ci.example` | See [Build and test variables](#build-and-test-variables) |
| `ignore-scripts` | `true` | Install dependencies without running their lifecycle scripts |
| `integration-tests` | `false` | ai-fastapi: run `pytest -m integration` with `RUN_INTEGRATION_TESTS=1` (exit 5, "no tests collected", passes) |
| `phase` | `all` | ios-swiftui: `static` (Linux checks), `build` (macOS build and tests) or `all`. Every other stack takes `all` |
| `database` | `true` | be-go, be-axum: run the database checks; `false` for a repo that owns no schema |
| `pgbouncer-tests` | `false` | be-go, be-axum: run `scripts/check/pooler.sh` behind PgBouncer (needs `database: true`) |
| `pgbouncer-max-prepared-statements` | `200` | PgBouncer's `max_prepared_statements` for `pgbouncer-tests`, a whole number |
| `xcode-version` | empty | ios-swiftui build: the first line of `xcodebuild -version` must read `Xcode <this>`; empty checks nothing |
| `scheme` | empty | ios-swiftui build: the Xcode scheme to build and test; empty uses the project's name |
| `node-version` | `22` | For `actions/setup-node` |
| `bun-version` | `1.4.2` | For `oven-sh/setup-bun`, when the package manager is bun |
| `uv-version` | `0.12.17` | For `astral-sh/setup-uv` (ai-fastapi, and the skill scan) |
| `python-version` | empty | ai-fastapi: the Python uv uses; empty reads `.python-version` or `requires-python` |
| `strict` | `true` | Fail when a check could not run |

The reusable workflows add `runs-on` (empty: the caller repository's `CI_RUNNER_FAST`, then
`CI_RUNNER`, then `ubuntu-latest`) and `timeout-minutes`. ai-fastapi's also takes two optional
secrets, `DATABASE_URL` and `REDIS_URL`, for the integration tests. ios-swiftui's `runs-on` picks
the macOS runner (empty: `CI_RUNNER_MACOS`, then `xcode-27`), `static-runs-on` the Linux one, and
`xcode-version` defaults to `27.0`.

## Build and test variables

The caller cannot set environment variables for a reusable workflow, yet a settings module that
validates at import time, or a build that reads `NEXT_PUBLIC_API_URL`, needs some. Commit them as
dummies in `.env.ci.example` (the name the `env-file` input defaults to):

```text
# Dummy values for the quality gate. Never a real secret: gitleaks scans this file.
DATABASE_URL=postgresql://ci:ci@localhost:5432/ci
NEXT_PUBLIC_API_URL=http://localhost:4000
```

The gate exports each `KEY=VALUE` line for the checks, prints only the names, and refuses a key
that would change how the runner or a toolchain behaves (`PATH`, `NODE_OPTIONS`, `LD_*`,
`GITHUB_*`, `GOFLAGS`, `CARGO_*`, `RUSTFLAGS`, `SQLX_*`, `DEVELOPER_DIR` and similar; Go's own
`GO…` names, not `GOOGLE_CLIENT_ID`). A variable already set in the environment keeps its value, so a secret
the caller passes wins over the file's dummy. The file must end in `.example`: agent-core's
settings let an agent read and edit `.env*.example` files and nothing else starting with `.env`.

## Calling it

Through the reusable workflow, which is what setup installs:

```yaml
jobs:
  quality-gate:
    permissions:
      contents: read
    uses: adhibuchori/agent-config-kit/.github/workflows/fe-nextjs-quality-gate.yml@<40-hex sha> # v1.0.0
```

Or as a step in your own job, after a checkout with `fetch-depth: 0`:

```yaml
- uses: adhibuchori/agent-config-kit/actions/quality-gate@<40-hex sha> # v1.0.0
  with:
    stack: be-hono
    base-ref: ${{ github.base_ref }}
```

Pin a full commit SHA with its release in the comment; `pinact run` resolves one for you. The
reusable workflows call this action as `$/actions/quality-gate`, GitHub's self-repository form, so
your pin on the workflow also pins this action and every script under `scripts/`. That form needs
github.com and runner 2.336.0 or newer; GitHub Enterprise Server does not support it, so there, call
the action directly with a SHA, as above.

By hand, from your repository's root (the scripts read no GitHub variable they need):

```bash
QG_STACK=be-hono QG_BASE=origin/dev bash path/to/agent-config-kit/actions/quality-gate/scripts/gate.sh
```

## Security

- The gate needs `contents: read` and no secret. It pushes nothing, uploads nothing, and the
  reusable workflows check out with `persist-credentials: false`.
- Every input reaches the scripts through `env:`, never as an expression inside a script.
- Text the pull request controls (file names, added lines, a diff) is printed with workflow
  commands switched off, so a line such as `::add-mask::` in a diff stays text.
- gitleaks is one exact release, checked against the SHA-256 in that release's checksums file
  before it runs (`scripts/install-gitleaks.sh`); so is every tool in `scripts/tools.lock`
  (`scripts/install-release.sh`). The PostgreSQL and PgBouncer images are pinned by digest.
  SkillSpector is the commit your `scripts/check/skills.sh` pins. The toolchain actions are pinned
  by commit SHA.
- No dependency cache is restored, so nothing from an earlier run changes what the gate checks.
