---
description: Check this repo against agent-fe-nextjs's installed files with --check (read-only, exits non-zero on drift or double hook wiring), or update them after a dry run you approve
argument-hint: "[--check]"
disable-model-invocation: true
allowed-tools: Read, Bash(command -v agent-sync), Bash(agent-sync check:*), Bash(agent-sync plan:*)
---

# Sync agent-fe-nextjs's files

Arguments: `$ARGUMENTS`

The engine is agent-core's `agent-sync`. Run `command -v agent-sync` first; if it prints nothing,
stop and ask the user to install or enable agent-core (`/plugin install agent-core@agent-config-kit`).
The templates path is written out in full because the Bash tool does not export
`CLAUDE_PLUGIN_ROOT`.

## With `--check`: report, write nothing

Run:

```bash
agent-sync check --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack fe-nextjs
```

Show its findings verbatim and report the exit code with its meaning. The output is the same, byte
for byte, on an unchanged repo, so CI can run the same command.

| Exit | Meaning |
| --- | --- |
| 0 | In sync |
| 1 | Drift: a managed file is missing, modified, stale or new, a block or a settings entry changed, or the versions differ |
| 4 | Double wiring: `.claude/settings.json` or `.claude/settings.local.json` runs a hook the plugins already run |
| 5 | Both 1 and 4 |
| 2 | Usage or I/O error (python3 missing, bad flags, unreadable templates) |
| 3 | Refused (for example, the project is inside the plugin folder) |

For each finding, say what fixes it:

- `double-wired`: remove that entry from the project's settings file; the plugin runs the hook.
- `modified`: the user changed a file the kit manages. A check script with a repo setting at its top
  (the class prefixes in `scripts/check/responsive.ts`, for example) is expected to be edited: keep
  the user's copy with
  `agent-sync own --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack fe-nextjs <path>`, or take
  the kit's version by deleting the file and running `/agent-fe-nextjs:sync`. Run `own` only when the
  user asks for it.
- `alias-missing` after a `package.json` appeared: `/agent-fe-nextjs:sync` without `--check` adds the
  missing package scripts.
- Anything else (`missing`, `stale`, `new`, `version`, a `block-*` or `settings-missing` finding):
  `/agent-fe-nextjs:sync` without `--check` repairs it after a draft.

Stop there: `--check` never writes.

## Without `--check`: draft, then write on "go"

1. Run
   `agent-sync plan --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack fe-nextjs`
   and show the output verbatim, digest included. A `modified` file is never touched; the draft names
   the two ways out above. End with: "Reply **go** to write exactly this."
2. Only on **go**, run
   `agent-sync apply --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack fe-nextjs --digest sha256:<hex>`
   with the digest from step 1. `apply` is left out of this command's allowed tools, so the permission
   prompt confirms it a second time. Exit 3 means the repo changed since the draft: show a new plan.
3. Run the `--check` command above and report the result. Remind the user to commit the changed files
   with `.claude/agent-config-kit.lock`.
