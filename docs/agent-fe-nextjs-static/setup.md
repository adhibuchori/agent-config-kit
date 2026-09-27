# setup

Command · agent-fe-nextjs-static · `/agent-fe-nextjs-static:setup [--answer id=value …]` · only you start it · writes only after you reply go · no network

## What it does

`/agent-fe-nextjs-static:setup` installs what a plugin cannot ship by itself into your repo: the static-site rules, anti-patterns, the site checks (static export, sitemap and robots, metadata, share images, JSON-LD, links, image, font and bundle budgets, security headers, accessibility), `site.config.json`, lint and budget configs, `public/_headers`, a pull-request-only CI caller, a CODEOWNERS starter and, if you want them, React Doctor and a DeepSeek review of each pull request.

It explores your repo, asks one question at a time with a recommended answer, shows the exact draft,
and writes only when you reply **go**. It never overwrites or deletes a file. It adds 12 package script(s) to an existing `package.json` (never creates one) and keeps any script you already have. The lock
`.claude/agent-config-kit.lock` is written last: it turns the kit's hooks on in this repo.

If agent-core is not set up in this repo yet, the same draft includes agent-core's layer first (its four questions come first). One setup, one lock.

It refuses (exit 3) a repo already set up with `agent-ai-fastapi`, `agent-be-hono`, `agent-docs-nextra`, `agent-fe-nextjs`: one primary stack per repo.

## When to reach for it

Once per repo, after you install the plugin:

```text
/agent-fe-nextjs-static:setup
/agent-fe-nextjs-static:setup --answer i18n=no
```

The questions (answer "ok" to take the recommended one):

| Question id | What it asks | Choices | Recommended |
| --- | --- | --- | --- |
| `i18n` | Does the site ship more than one language (next-intl)? | yes / no | `no` |
| `headers` | Will the host read the site's response headers from a _headers file in public/? | yes / no | `yes` |
| `lighthouse` | Hold the pages to Core Web Vitals budgets with Lighthouse CI (lighthouserc.json)? | yes / no | `yes` |
| `ci-gate` | Add the pull-request quality gate workflow (.github/workflows/quality-gate.yaml)? | yes / no | `yes` |
| `react-doctor` | Run React Doctor on pull requests (advisory review comments and a commit status; it never fails the check)? | yes / no | `no` |
| `deepseek-review` | Review each pull request with DeepSeek, a low-cost paid AI model (.github/workflows/deepseek-review.yml)? | yes / no | `no` |

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
- `/agent-fe-nextjs-static:sync --check` then ends with `result: in sync (0 findings; exit 0)`.
- Every CI caller is pinned to a release commit of agent-config-kit. A caller that still holds the
  all-zero release placeholder (a new caller, until the plugin release that pins it) is not
  installed: the draft shows `warn     .github/workflows/<name>.y…ml  not installed: …`, `--check`
  lists it as `held`, and the next release installs it through sync.
- `git status` shows the new files; commit them with the lock.

## Where it fits

The first command you run from [agent-fe-nextjs-static](../../plugins/agent-fe-nextjs-static/README.md). Afterwards, [/agent-fe-nextjs-static:sync](sync.md) keeps the repo in line with the plugin.
