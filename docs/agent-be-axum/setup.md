# setup

Command · agent-be-axum · `/agent-be-axum:setup [--answer id=value …]` · only you start it · writes only after you reply go · no network

## What it does

`/agent-be-axum:setup` installs what a plugin cannot ship by itself into your Rust + Axum repo: backend rules (the service layout, PostgreSQL, testing, error codes, coverage), anti-patterns, a service skeleton whose error module, extractor, layers and tests already pass the gates, the gate scripts (rustfmt, cargo policy, Rust source checks, migrations, coverage, the pooler tier) with `gates.list` and `.githooks/pre-commit`, clippy, rustfmt, cargo-deny, nextest and toolchain config, `scripts/check/ci-env.sh` with a seeded `.env.ci.example`, a pull-request-only CI caller, an optional DeepSeek review of each pull request, PR templates and a CODEOWNERS starter.

It explores your repo, asks one question at a time with a recommended answer, shows the exact draft,
and writes only when you reply **go**. It never overwrites or deletes a file, and it adds no
`package.json`. A new repo gets `Cargo.toml` from a starter; an existing one gets a `by-hand` line
naming the lint and release-profile block to paste. The lock `.claude/agent-config-kit.lock` is
written last: it turns the kit's hooks on in this repo.

If agent-core is not set up in this repo yet, the same draft includes agent-core's layer first (its four questions come first). One setup, one lock.

It refuses (exit 3) a repo already set up with `agent-ai-fastapi`, `agent-be-go`, `agent-be-hono`, `agent-docs-nextra`, `agent-fe-nextjs`, `agent-fe-nextjs-static` or `agent-ios-swiftui`: one primary stack per repo.

## When to reach for it

Once per repo, after you install the plugin:

```text
/agent-be-axum:setup
/agent-be-axum:setup --answer migrations=no
```

The questions (answer "ok" to take the recommended one):

| Question id | What it asks | Choices | Recommended |
| --- | --- | --- | --- |
| `migrations` | Does this service own its database schema, so its sqlx migrations live in migrations/ here? | yes / no | `yes` |
| `ci-gate` | Run agent-config-kit's Rust + Axum quality gate on every pull request (.github/workflows/quality-gate.yml)? | yes / no | `yes` |
| `deepseek-review` | Review each pull request with DeepSeek, a low-cost paid AI model (.github/workflows/deepseek-review.yml)? | yes / no | `no` |
| `pr-templates` | Add pull-request templates for work pull requests and dev → prod promotions (.github/PULL_REQUEST_TEMPLATE/)? | yes / no | `yes` |
| `analytics` | Does an agent need to read a self-hosted analytics API from this repo? | yes / no | `no` |
| `serena-workspace` | Do you open several repositories as one Serena workspace? | yes / no | `no` |

The draft lists every action: `create`, `same`, `keep`, `seed`, `merge`, `conflict`, `block`,
`alias`, `by-hand`, `warn` and `lock`, then a `digest`. `apply` is not pre-approved, so your
permission prompt is a second confirmation.

## Prerequisites

- agent-core enabled, with python3 3.8 or newer.
- For the gates afterwards: the toolchain `rust-toolchain.toml` names, cargo-llvm-cov, cargo-nextest,
  Node 20 or newer, gitleaks, and PostgreSQL 18 for the database tier. Setup installs none of them.

## Common questions

**Will it overwrite my files?**
No. A file that exists is listed as `keep` and left alone. Only three existing files are edited, each shown in the draft: an additive merge of `.claude/settings.json` (never its `hooks`), and one managed block each in `.gitignore` and `CLAUDE.md`.

**What happens to my existing crate?**
Every skeleton file that is missing is seeded next to your code, and none of them is wired into your
`lib.rs`. The tests name the library `service`. Adapt them, or delete the ones you do not want.

**What do I do right after setup?**
Run `cargo generate-lockfile` once in a new repo and commit `Cargo.lock`, turn the commit gate on
with `git config core.hooksPath .githooks`, and set `PROBLEM_TYPE_BASE` in `src/platform/error.rs`
before the first release.

**It says `command -v agent-setup` found nothing.**
agent-core is not enabled in this session, or you are on claude.ai or Cowork, which do not install plugins with a `bin/` folder. Enable agent-core with `/plugin` and restart.

**Apply exited 3.**
The repo changed since the draft (the digest no longer matches). Run setup again to see a new draft.

## It's working if

- The draft ends with a `digest sha256:…` line, and after **go** the last line apply prints is
  `wrote    .claude/agent-config-kit.lock`.
- `/agent-be-axum:sync --check` then ends with `result: in sync (0 findings; exit 0)`.
- After the by-hand steps, `bash scripts/check/gates.sh` passes on the seeded skeleton.
- Every CI caller is pinned to a release commit of agent-config-kit. A caller that still holds the
  all-zero release placeholder (a new caller, until the plugin release that pins it) is not
  installed: the draft shows `warn     .github/workflows/<name>.y…ml  not installed: …`, `--check`
  lists it as `held`, and the next release installs it through sync.

## Where it fits

The first command you run from [agent-be-axum](../../plugins/agent-be-axum/README.md). Afterwards, [/agent-be-axum:sync](sync.md) keeps the repo in line with the plugin.
