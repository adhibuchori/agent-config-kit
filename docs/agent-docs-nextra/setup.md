# setup

Command · agent-docs-nextra · `/agent-docs-nextra:setup [--answer id=value …]` · only you start it · writes only after you reply go · no network

## What it does

`/agent-docs-nextra:setup` installs what a plugin cannot ship by itself into your repo: the docs-content rule, anti-patterns, the gate scripts and comment checks, oxlint, oxfmt and knip config, the env helper, a pull-request-only CI caller and, if you want them, the changelog and deploy workflows.

It explores your repo, asks one question at a time with a recommended answer, shows the exact draft,
and writes only when you reply **go**. It never overwrites or deletes a file. It adds 6 package script(s) to an existing `package.json` (never creates one) and keeps any script you already have. The lock
`.claude/agent-config-kit.lock` is written last: it turns the kit's hooks on in this repo.

If agent-core is not set up in this repo yet, the same draft includes agent-core's layer first (its four questions come first). One setup, one lock.

It refuses (exit 3) a repo already set up with `agent-ai-fastapi`, `agent-be-hono`, `agent-fe-nextjs`, `agent-fe-nextjs-static`: one primary stack per repo.

## When to reach for it

Once per repo, after you install the plugin:

```text
/agent-docs-nextra:setup
/agent-docs-nextra:setup --answer generated-pages=no
```

The questions (answer "ok" to take the recommended one):

| Question id | What it asks | Choices | Recommended |
| --- | --- | --- | --- |
| `generated-pages` | Do generators write pages into this site: an API reference under content/technical and a changelog at content/changelog.mdx? | yes / no | `no` |
| `ci-pipeline` | Should CI regenerate those pages and deploy the static export to Cloudflare Workers when a pull request merges into prod? | yes / no | `no` |
| `react-doctor` | Run React Doctor on pull requests into dev and prod (advisory review comments and a commit status; it never fails the check)? | yes / no | `no` |
| `analytics` | Does an agent need to read an analytics API for this site? | yes / no | `no` |

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
- `/agent-docs-nextra:sync --check` then ends with `result: in sync (0 findings; exit 0)`.
- While this release's CI caller still holds the release placeholder pin, the draft shows
  `warn     .github/workflows/quality-gate.y…ml  not installed: …` and `--check` lists it as
  `held`; the next release installs it through sync.
- `git status` shows the new files; commit them with the lock.

## Where it fits

The first command you run from [agent-docs-nextra](../../plugins/agent-docs-nextra/README.md). Afterwards, [/agent-docs-nextra:sync](sync.md) keeps the repo in line with the plugin.
