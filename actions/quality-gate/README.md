# quality-gate action

The steps behind the five reusable quality-gate workflows in
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

**Strict.** Every check passes, fails, or is listed as a check that did not run: no gitleaks build
for the runner, no coverage report, no `gates.list`. With `strict: true` (the default), a check that
did not run fails the gate, because a gate that quietly skipped its secret scan looks the same as
one that passed it. The summary at the end of the log lists both.

## Inputs

| Input | Default | What it does |
| --- | --- | --- |
| `stack` | (required) | `fe-nextjs`, `fe-nextjs-static`, `be-hono`, `ai-fastapi` or `docs-nextra` |
| `base-ref` | (required) | The branch the pull request merges into; `dev` resolves to `origin/dev`. The reusable workflows pass `github.base_ref` |
| `package-manager` | `auto` | `auto` reads the lockfile (`bun.lock`, `pnpm-lock.yaml`, `yarn.lock`, `package-lock.json`); or `bun`, `pnpm`, `npm`, `yarn`. ai-fastapi always uses uv |
| `coverage-threshold` | stack default | The floor, 0 to 100 (empty: 100, or 0 for fe-nextjs-static and docs-nextra), read from the report your tests wrote: `lcov.info`, `coverage-summary.json` or `coverage-final.json` under `coverage/` (or where `gates.sh` put it), or `.coverage` for Python. Lines, statements, functions and branches each count when the report measured them. `0` turns it off; your test runner's own thresholds still apply |
| `env-file` | `.env.ci.example` | See [Build and test variables](#build-and-test-variables) |
| `ignore-scripts` | `true` | Install dependencies without running their lifecycle scripts |
| `integration-tests` | `false` | ai-fastapi: run `pytest -m integration` with `RUN_INTEGRATION_TESTS=1` (exit 5, "no tests collected", passes) |
| `node-version` | `22` | For `actions/setup-node` |
| `bun-version` | `1.4.2` | For `oven-sh/setup-bun`, when the package manager is bun |
| `uv-version` | `0.12.17` | For `astral-sh/setup-uv` (ai-fastapi, and the skill scan) |
| `python-version` | empty | ai-fastapi: the Python uv uses; empty reads `.python-version` or `requires-python` |
| `strict` | `true` | Fail when a check could not run |

The reusable workflows add `runs-on` (empty: the caller repository's `CI_RUNNER_FAST`, then
`CI_RUNNER`, then `ubuntu-latest`) and `timeout-minutes`. ai-fastapi's also takes two optional
secrets, `DATABASE_URL` and `REDIS_URL`, for the integration tests.

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
`GITHUB_*` and similar). A variable already set in the environment keeps its value, so a secret
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
  before it runs (`scripts/install-gitleaks.sh`). SkillSpector is the commit your
  `scripts/check/skills.sh` pins. The toolchain actions are pinned by commit SHA.
- No dependency cache is restored, so nothing from an earlier run changes what the gate checks.
