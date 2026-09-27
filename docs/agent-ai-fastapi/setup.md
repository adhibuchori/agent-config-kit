# setup

Command · agent-ai-fastapi · `/agent-ai-fastapi:setup [--answer id=value …]` · only you start it · writes only after you reply go · no network

## What it does

`/agent-ai-fastapi:setup` installs what a plugin cannot ship by itself into your repo: backend and Python rules (FastAPI, providers, performance, testing, coverage), anti-patterns, the pre-commit config, the gate list, a vulture whitelist, a pull-request-only CI caller, PR templates and, if you want it, the pipeline example; `pyproject.toml` tool sections are printed for you to add by hand.

It explores your repo, asks one question at a time with a recommended answer, shows the exact draft,
and writes only when you reply **go**. It never overwrites or deletes a file. The lock
`.claude/agent-config-kit.lock` is written last: it turns the kit's hooks on in this repo.

If agent-core is not set up in this repo yet, the same draft includes agent-core's layer first (its four questions come first). One setup, one lock.

It refuses (exit 3) a repo already set up with `agent-be-hono`, `agent-docs-nextra`, `agent-fe-nextjs`, `agent-fe-nextjs-static`: one primary stack per repo.

## When to reach for it

Once per repo, after you install the plugin:

```text
/agent-ai-fastapi:setup
/agent-ai-fastapi:setup --answer pipeline=no
```

The questions (answer "ok" to take the recommended one):

| Question id | What it asks | Choices | Recommended |
| --- | --- | --- | --- |
| `pipeline` | Does this service own its database schema and run Alembic migrations here (the pipeline shape)? | yes / no | `no` |
| `ci-gate` | Run agent-config-kit's FastAPI quality gate on every pull request into dev, prod, main or master (.github/workflows/quality-gate.yml)? | yes / no | `yes` |
| `pr-templates` | Add pull-request templates for work pull requests and dev → prod promotions (.github/PULL_REQUEST_TEMPLATE/)? | yes / no | `yes` |
| `analytics` | Does an agent need to read a self-hosted analytics API from this repo? | yes / no | `no` |
| `serena-workspace` | Do you open several repositories as one Serena workspace (for example this service and the repo that owns its schema)? | yes / no | `no` |

The draft lists every action: `create`, `same`, `keep`, `seed`, `merge`, `conflict`, `block`,
`alias`, `by-hand`, `warn` and `lock`, then a `digest`. `apply` is not pre-approved, so your
permission prompt is a second confirmation.

Some files cannot be merged safely, so the draft prints a `by-hand` line for `pyproject.toml` with the text to add yourself.

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
- `/agent-ai-fastapi:sync --check` then ends with `result: in sync (0 findings; exit 0)`.
- The CI caller is pinned to the v1.0.0 release commit. A caller that still holds the all-zero
  release placeholder (as in 1.0.0) is not installed: the draft shows
  `warn     .github/workflows/quality-gate.y…ml  not installed: …`, `--check` lists it as `held`,
  and the next release installs it through sync.
- `git status` shows the new files; commit them with the lock.

## Where it fits

The first command you run from [agent-ai-fastapi](../../plugins/agent-ai-fastapi/README.md). Afterwards, [/agent-ai-fastapi:sync](sync.md) keeps the repo in line with the plugin.
