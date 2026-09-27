---
description: Compare this repo with what agent-deploy's setup installed; --check reports drift and double hook wiring (read-only, non-zero exit), otherwise shows a sync draft and writes it on go
argument-hint: "[--check]"
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Bash(git status:*), Bash(command -v agent-sync), Bash(agent-sync check:*), Bash(agent-sync plan:*)
---

# /agent-deploy:sync — Keep agent-deploy's Setup In Sync

**Arguments:** $ARGUMENTS

The engine runs as `agent-sync`, a program in agent-core's `bin/`. If `command -v agent-sync` finds
nothing, agent-core is not enabled in this session: ask the user to install or enable it
(`/plugin install agent-core@agent-config-kit`) and restart. The templates path is written out in
full below because the Bash tool does not export `CLAUDE_PLUGIN_ROOT`.

## With `--check` (read-only, deterministic)

```bash
agent-sync check --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack deploy --project "$PWD"
```

Report its lines verbatim and its exit code: 0 in sync, 1 drift, 4 double wiring, 5 both, 2 a usage
or I/O error. Write nothing. It covers agent-deploy and agent-core together, and the same command,
run from a checkout of the kit, is what CI runs.

What each finding means here:

- `missing`, `modified`, `mode`: `scripts/deploy/verify-deploy.sh` or `trigger-deploy.sh` is gone,
  was edited, or lost its exec bit (or the same for one of agent-core's files).
- `stale`, `new`, `removed-upstream`, `version`: the installed plugin differs from the one the lock
  records; a plan brings the files up to date.
- `settings-missing`: one of the `ask` rules for the deploy scripts is gone from
  `.claude/settings.json`, so Claude could run a network script without asking.
- `block-*`, `alias-missing`: the `.gitignore` or `CLAUDE.md` block, or agent-core's `unlock` script,
  changed.
- `double-wired`: the project settings wire a hook script agent-core also runs, so it would run
  twice. Remove that entry from the project settings.
- `no-lock`: setup has not run here: `/agent-deploy:setup`.
- `kept`, `owned`, `seeded`, `unchecked`: information only.

## Without `--check`

1. Draft:

   ```bash
   agent-sync plan --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack deploy --project "$PWD"
   ```

   Show it verbatim with its digest. Sync creates what is missing or new, replaces a file only while
   its bytes still equal what setup wrote (`replace`), restores exec bits, and re-applies the
   settings and block merges. It never touches a file the user edited (`modified`): the draft names
   the two ways out, `agent-sync own <path>` to keep the user's copy, or deleting it and syncing again
   to take the kit's. End with: "Reply **go** to write exactly this."

2. On **go**, and only then:

   ```bash
   agent-sync apply --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack deploy --project "$PWD" --digest <digest from step 1>
   ```

   `apply` is not pre-approved, so the user's permission prompt confirms it a second time. Exit 3
   means the project changed since the draft: show a new plan.

3. Run the `--check` command above and report the result. Remind the user to commit the changed
   files and the lock.

To keep an edited script as the repo's own, the user approves
`agent-sync own --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack deploy --project "$PWD" <path>`;
`--undo` hands it back to the kit.
