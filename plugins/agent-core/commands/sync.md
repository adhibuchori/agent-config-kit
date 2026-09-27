---
description: Compare this repo with what agent-core's setup installed; --check reports drift and double hook wiring (read-only, non-zero exit), otherwise shows a sync draft and writes it on go
argument-hint: "[--check]"
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Bash(git status:*), Bash(agent-sync check:*), Bash(agent-sync plan:*)
---

# /agent-core:sync — Keep agent-core's Setup In Sync

**Arguments:** $ARGUMENTS

The engine runs as `agent-sync`, a program in agent-core's `bin/`. If `command -v agent-sync` finds
nothing, agent-core is not enabled in this session: ask the user to enable it and restart.

## With `--check` (read-only, deterministic)

```bash
agent-sync check --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack common --project "$PWD"
```

Report its lines verbatim and its exit code: 0 in sync, 1 drift, 4 double wiring, 5 both, 2 a usage
or I/O error. Write nothing. The same command, run from a checkout of the kit, is what CI runs.

What each finding means:

- `missing`, `modified`, `mode`: a file setup wrote is gone, was edited, or lost its exec bit.
- `stale`, `new`, `removed-upstream`, `version`: the installed agent-core differs from the one the
  lock records.
- `settings-missing`, `block-*`, `alias-missing`: a settings entry, the `.gitignore` or `CLAUDE.md`
  block, or the `unlock` script changed.
- `double-wired`: `.claude/settings.json` (or `settings.local.json`) wires a hook script agent-core
  also runs, so it would run twice. Remove that entry from the project settings.
- `no-lock`: setup has not run here: `/agent-core:setup`.
- `kept`, `owned`, `seeded`, `unchecked`: information only.

## Without `--check`

1. Draft:

   ```bash
   agent-sync plan --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack common --project "$PWD"
   ```

   Show it verbatim with its digest. Its first line names the project folder (`project .` at the
   repo root): if an earlier `cd` left the shell elsewhere, `cd` back to the root and plan again. Sync creates what is missing or new, replaces a file only while
   its bytes still equal what setup wrote (`replace`), restores exec bits, and re-applies the
   settings, block and alias merges. It never touches a file the user edited (`modified`): the
   draft names the two ways out, `agent-sync own <path>` to keep the user's copy, or deleting it and
   syncing again to take the kit's. End with: "Reply **go** to write exactly this."

2. On **go**, and only then:

   ```bash
   agent-sync apply --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack common --project "$PWD" --digest <digest from step 1>
   ```

   `apply` is not pre-approved, so the user's permission prompt confirms it a second time. Exit 3
   means the project changed since the draft: show a new plan.

3. Run the `--check` command above and report the result. Remind the user to commit the changed
   files and the lock.

To keep an edited file as the repo's own, the user approves
`agent-sync own --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack common --project "$PWD" <path>`;
`--undo` hands it back to the kit.
