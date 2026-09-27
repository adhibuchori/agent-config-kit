# setup

Command · agent-be-hono · `/agent-be-hono:setup [--answer id=value …]` · only you start it · writes only after you reply go · no network

## What it does

`/agent-be-hono:setup` installs what a plugin cannot ship by itself into your repo: backend rules (Hono, Drizzle, performance, testing), anti-patterns, the gate scripts (constants, coverage, migrations, index coverage, module mocks), `scripts/check/ci-env.sh` with a seeded `.env.ci.example` so the unit tests run with CI's variables and nothing from your shell or `.env`, oxlint, oxfmt, knip and bun test config, the husky pre-commit hook, a pull-request-only CI caller, an optional DeepSeek review of each pull request, PR templates and a CODEOWNERS starter, plus the package scripts they need.

It explores your repo, asks one question at a time with a recommended answer, shows the exact draft,
and writes only when you reply **go**. It never overwrites or deletes a file. It adds 13 package script(s) to an existing `package.json` (never creates one) and keeps any script you already have. The lock
`.claude/agent-config-kit.lock` is written last: it turns the kit's hooks on in this repo.

If agent-core is not set up in this repo yet, the same draft includes agent-core's layer first (its four questions come first). One setup, one lock.

It refuses (exit 3) a repo already set up with `agent-ai-fastapi`, `agent-docs-nextra`, `agent-fe-nextjs`, `agent-fe-nextjs-static`: one primary stack per repo.

## When to reach for it

Once per repo, after you install the plugin:

```text
/agent-be-hono:setup
/agent-be-hono:setup --answer ci-gate=yes
```

The questions (answer "ok" to take the recommended one):

| Question id | What it asks | Choices | Recommended |
| --- | --- | --- | --- |
| `ci-gate` | Run agent-config-kit's backend quality gate on every pull request (.github/workflows/quality-gate.yml)? | yes / no | `yes` |
| `deepseek-review` | Review each pull request with DeepSeek, a low-cost paid AI model (.github/workflows/deepseek-review.yml)? | yes / no | `no` |
| `pr-templates` | Add pull-request templates for work pull requests and dev → prod promotions (.github/PULL_REQUEST_TEMPLATE/)? | yes / no | `yes` |
| `analytics` | Does an agent need to read a self-hosted analytics API from this repo? | yes / no | `no` |
| `serena-workspace` | Do you open several repositories as one Serena workspace? | yes / no | `no` |

The draft lists every action: `create`, `same`, `keep`, `seed`, `merge`, `conflict`, `block`,
`alias`, `by-hand`, `warn` and `lock`, then a `digest`. `apply` is not pre-approved, so your
permission prompt is a second confirmation.

## Common questions

**Will it overwrite my files?**
No. A file that exists is listed as `keep` and left alone. Only four existing files are edited, each shown in the draft: an additive merge of `.claude/settings.json` (never its `hooks`), one managed block each in `.gitignore` and `CLAUDE.md`, and missing scripts in `package.json`.

**It says `command -v agent-setup` found nothing.**
agent-core is not enabled in this session, or you are on claude.ai or Cowork, which do not install plugins with a `bin/` folder. Enable agent-core with `/plugin` and restart.

**Apply exited 3.**
The repo changed since the draft (the digest no longer matches). Run setup again to see a new draft.

**What does `warn … double-wired` mean?**
Your `.claude/settings.json` already wires a hook script the plugin also runs, so it would run twice. Delete that entry from your settings.

## It's working if

- The draft ends with a `digest sha256:…` line, and after **go** the last line apply prints is
  `wrote    .claude/agent-config-kit.lock`.
- `/agent-be-hono:sync --check` then ends with `result: in sync (0 findings; exit 0)`.
- Every CI caller is pinned to a release commit of agent-config-kit. A caller that still holds the
  all-zero release placeholder (a new caller, until the plugin release that pins it) is not
  installed: the draft shows `warn     .github/workflows/<name>.y…ml  not installed: …`, `--check`
  lists it as `held`, and the next release installs it through sync.
- `git status` shows the new files; commit them with the lock.

## Where it fits

The first command you run from [agent-be-hono](../../plugins/agent-be-hono/README.md). Afterwards, [/agent-be-hono:sync](sync.md) keeps the repo in line with the plugin.
