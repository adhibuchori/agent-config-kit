# setup

Command · agent-core · `/agent-core:setup [--answer id=value …]` · only you start it · writes only after you reply go · no network

## What it does

`/agent-core:setup` installs what a plugin cannot ship by itself into your repo: permissions and the Bash sandbox in `.claude/settings.json`, the TypeScript or Python type and dead-code rules, the working agreements, the check scripts (`gates.sh`, `ai-config.sh`, `skills.sh`, `pr-ready.sh`), the unlock script and the `.env` helpers, `docs/unlock.md`, the example ops docs and, if you want it, the kit's `.mcp.json`.

It explores your repo, asks one question at a time with a recommended answer, shows the exact draft,
and writes only when you reply **go**. It never overwrites or deletes a file. It adds 1 package script(s) to an existing `package.json` (never creates one) and keeps any script you already have. The lock
`.claude/agent-config-kit.lock` is written last: it turns the kit's hooks on in this repo.

## When to reach for it

Once per repo, after you install the plugin:

```text
/agent-core:setup
/agent-core:setup --answer language=typescript
```

The questions (answer "ok" to take the recommended one):

| Question id | What it asks | Choices | Recommended |
| --- | --- | --- | --- |
| `language` | Which languages does this repo's code use? | typescript / python / both | `typescript` |
| `sandbox` | Turn on Claude Code's Bash sandbox for this repo? | yes / no | `yes` |
| `mcp` | Add the kit's .mcp.json (Serena, GitHub, Context7, and read-only dev and production database servers)? | yes / no | `yes` |
| `team-plugins` | Offer these plugins to teammates who open the repo? | yes / no | `yes` |

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
- `/agent-core:sync --check` then ends with `result: in sync (0 findings; exit 0)`.
- `git status` shows the new files; commit them with the lock.

## Where it fits

The first command you run from [agent-core](../../plugins/agent-core/README.md). Afterwards, [/agent-core:sync](sync.md) keeps the repo in line with the plugin.
