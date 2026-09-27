# sync

Command · agent-fe-nextjs-static · `/agent-fe-nextjs-static:sync [--check]` · only you start it · `--check` reads only; otherwise writes after go · no network

## What it does

`/agent-fe-nextjs-static:sync` compares your repo with what `/agent-fe-nextjs-static:setup` installed, using the lock.
With `--check` it only reports, deterministically, and exits non-zero on drift or double hook
wiring. Without it, it shows a draft that brings unchanged files up to date and writes it on **go**.
It never touches a file you edited.

## When to reach for it

After you update the plugin, or any time you want to know whether the repo still matches:

```text
/agent-fe-nextjs-static:sync --check
/agent-fe-nextjs-static:sync
```

Exit codes of `--check`: 0 in sync, 1 drift, 4 double wiring, 5 both, 2 a usage or read error.
Each finding is one line, `<kind>  <path>  <detail>`: `missing`, `modified`, `mode`, `stale`, `new`,
`removed-upstream`, `settings-missing`, `block-modified`, `block-stale`, `block-missing`,
`alias-missing`, `version`, `no-lock` and `double-wired`, plus the information-only `kept`, `owned`,
`seeded` and `unchecked`.

**Not for:** a repo where setup never ran (it reports `no-lock`); use
[/agent-fe-nextjs-static:setup](setup.md) instead.

## Common questions

**It says `modified` for a file I changed on purpose.**
Keep your copy as the repo's own with `agent-sync own <path>` (the draft shows the full command); `own --undo` hands it back. Or delete your copy and sync again to take the kit's.

**Can CI run the check?**
Yes. `agent-sync check` runs from a checkout of this repo without Claude Code: `plugins/agent-core/bin/agent-sync check --templates plugins/agent-fe-nextjs-static/templates --stack fe-nextjs-static --project <repo>`.

**Does sync ever overwrite my work?**
It replaces a file only while its bytes still equal what the kit wrote (`stale`), so no edit of yours is lost.

## It's working if

- `/agent-fe-nextjs-static:sync --check` prints `result: in sync (0 findings; exit 0)`, or only information lines.

## Where it fits

The partner of [/agent-fe-nextjs-static:setup](setup.md) in [agent-fe-nextjs-static](../../plugins/agent-fe-nextjs-static/README.md). See [upgrading](../../README.md#upgrade-and-uninstall).
