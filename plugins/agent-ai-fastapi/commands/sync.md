---
description: Check this repo against agent-ai-fastapi's installed files with --check (read-only, exits non-zero on drift or double hook wiring), hand a managed file over with own, or update the files after a dry run you approve
argument-hint: "[--check | own [--undo] <path>...]"
disable-model-invocation: true
allowed-tools: Read, Bash(command -v agent-sync), Bash(agent-sync check:*), Bash(agent-sync plan:*)
---

# Sync agent-ai-fastapi's files

Arguments: `$ARGUMENTS`

The engine is agent-core's `agent-sync`. Run `command -v agent-sync` first; if it prints nothing,
stop and ask the user to install or enable agent-core (`/plugin install agent-core@agent-config-kit`).
The templates path is written out in full because the Bash tool does not export
`CLAUDE_PLUGIN_ROOT`.

## With `--check`: report, write nothing

Run:

```bash
agent-sync check --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack ai-fastapi
```

Show its findings verbatim and report the exit code with its meaning. The output is the same on
every run against an unchanged repo, so CI can run the same command.

| Exit | Meaning |
| --- | --- |
| 0 | In sync |
| 1 | Drift: a managed file is missing, modified, stale or new, a block or a settings entry changed, or the versions differ |
| 4 | Double wiring: `.claude/settings.json` or `.claude/settings.local.json` runs a hook the plugins already run (for example `migration-guard.sh`) |
| 5 | Both 1 and 4 |
| 2 | Usage or I/O error (python3 missing, bad flags, unreadable templates) |
| 3 | Refused (for example, the project is inside the plugin folder) |

For each finding, say what fixes it:

- `double-wired`: remove that entry from the project's settings file; the plugin runs the hook.
- `modified`: the user changed a file the kit manages (a rule under `.claude/rules/`, an
  anti-pattern entry, `scripts/check/coverage-policy.mjs`, the CI caller). Keep their copy with
  `/agent-ai-fastapi:sync own <path>`, or take the kit's version by deleting the file and running
  `/agent-ai-fastapi:sync`.
- `missing` for a rule the user deleted on purpose (the pipeline shape drops `fastapi.md`,
  `performance.md` and `testing.md` from `.claude/rules/backend/` in a repo that serves no HTTP):
  `own` it, and it is no longer checked.
- Anything else (`missing`, `stale`, `new`, `version`, a `block-*` or `settings-missing` finding):
  `/agent-ai-fastapi:sync` without `--check` repairs it after a draft.

Seeded files (the starters, `pyproject.toml`, `.pre-commit-config.yaml`, `scripts/check/gates.list`,
the vulture whitelist, `.dockerignore`, the PR templates, the pipeline example, agent-core's `.gitleaks.toml` and
every other `seed` line of the setup draft) are the project's own after setup: `--check` lists them
as `seeded`, never as drift. Stop there: `--check` never writes.

## With `own`: hand a managed file to the project

Only when the user asked for it in the arguments, run:

```bash
agent-sync own --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack ai-fastapi <path> ...
```

(`own --undo <path>` hands a path back to the kit.) It changes only the lock file, and it is left out
of this command's allowed tools, so the permission prompt confirms it. Report what it printed, then
run the `--check` command above.

## Otherwise: draft, then write on "go"

1. Run
   `agent-sync plan --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack ai-fastapi`
   and show the output verbatim, digest included. A `modified` file is never touched; the draft names
   the two ways out above. A new pin for `.github/workflows/quality-gate.yml` arrives this way, as a
   `stale` file replaced. End with: "Reply **go** to write exactly this."
2. Only on **go**, run
   `agent-sync apply --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack ai-fastapi --digest sha256:<hex>`
   with the digest from step 1. `apply` is left out of this command's allowed tools, so the permission
   prompt confirms it a second time. Exit 3 means the repo changed since the draft: show a new plan.
3. Run the `--check` command above and report the result. Remind the user to commit the changed files
   with `.claude/agent-config-kit.lock`.
