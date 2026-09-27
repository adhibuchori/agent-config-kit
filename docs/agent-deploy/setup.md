# setup

Command · agent-deploy · `/agent-deploy:setup [--answer id=value …]` · only you start it · writes only after you reply go · no network

## What it does

`/agent-deploy:setup` installs what a plugin cannot ship by itself into your repo: the outside smoke test `scripts/deploy/verify-deploy.sh`, the optional deploy-webhook trigger, and ask-first permissions for both.

It explores your repo, asks one question at a time with a recommended answer, shows the exact draft,
and writes only when you reply **go**. It never overwrites or deletes a file. The lock
`.claude/agent-config-kit.lock` is written last: it turns the kit's hooks on in this repo.

If agent-core is not set up in this repo yet, the same draft includes agent-core's layer first (its four questions come first). One setup, one lock.

## When to reach for it

Once per repo, after you install the plugin:

```text
/agent-deploy:setup
/agent-deploy:setup --answer webhook=no
```

The questions (answer "ok" to take the recommended one):

| Question id | What it asks | Choices | Recommended |
| --- | --- | --- | --- |
| `webhook` | Does a deploy start when something POSTs to a deploy webhook URL? | yes / no | `no` |

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
- `/agent-deploy:sync --check` then ends with `result: in sync (0 findings; exit 0)`.
- `git status` shows the new files; commit them with the lock.

## Where it fits

The first command you run from [agent-deploy](../../plugins/agent-deploy/README.md). Afterwards, [/agent-deploy:sync](sync.md) keeps the repo in line with the plugin.
