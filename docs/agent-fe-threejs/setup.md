# setup

Command · agent-fe-threejs · `/agent-fe-threejs:setup [--answer id=value …]` · only you start it · writes only after you reply go · no network

## What it does

`/agent-fe-threejs:setup` installs what a plugin cannot ship by itself into your repo: the 3D scene rule `.claude/rules/web/3d.md`, the asset budget check `scripts/check/3d-budget.mjs` with its config, and `docs/3d-skills.md`.

It explores your repo, asks one question at a time with a recommended answer, shows the exact draft,
and writes only when you reply **go**. It never overwrites or deletes a file. The lock
`.claude/agent-config-kit.lock` is written last: it turns the kit's hooks on in this repo.

If agent-core is not set up in this repo yet, the same draft includes agent-core's layer first (its four questions come first). One setup, one lock.

## When to reach for it

Once per repo, after you install the plugin:

```text
/agent-fe-threejs:setup
/agent-fe-threejs:setup --answer language=typescript
```

The questions (answer "ok" to take the recommended one):

This plugin asks no questions of its own; agent-core's questions come first when agent-core is not set up yet.

The draft lists every action: `create`, `same`, `keep`, `seed`, `merge`, `conflict`, `block`,
`alias`, `by-hand`, `warn` and `lock`, then a `digest`. `apply` is not pre-approved, so your
permission prompt is a second confirmation.

Some files cannot be merged safely, so the draft prints a `by-hand` line for `.claude/settings.json`, `scripts/check/gates.list` with the text to add yourself.

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
- `/agent-fe-threejs:sync --check` then ends with `result: in sync (0 findings; exit 0)`.
- `git status` shows the new files; commit them with the lock.

## Where it fits

The first command you run from [agent-fe-threejs](../../plugins/agent-fe-threejs/README.md). Afterwards, [/agent-fe-threejs:sync](sync.md) keeps the repo in line with the plugin.
