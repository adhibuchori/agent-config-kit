# 1. Plugins cannot carry permissions, so setup installs them

- Status: accepted
- Date: 2026-09-26

## Context

The kit's guardrails are more than hooks. They rely on permission rules (`deny` for pushes to
protected branches and for reading `.env*`, `ask` for the unlock script), on Claude Code's Bash
sandbox, on `.claude/rules/` that load per file type, and on check scripts the pre-commit gate and
CI run.

A Claude Code plugin can ship hooks, commands, agents and skills. Its `settings.json` honours only
`agent` and `subagentStatusLine`: permissions, the sandbox and rules cannot come from a plugin.
Installed plugins are also copied into a cache without the rest of this repository, so nothing can
be read from outside a plugin's own folder at run time.

## Decision

Each plugin ships its files as templates under `plugins/<plugin>/templates/<stack>/`, and a
`/<plugin>:setup` command installs them into the user's repo through agent-core's engine
(`agent-setup`, `agent-sync`):

- explore the repo, ask one question at a time with a recommended answer, show the full draft,
  and write only on **go**, with a digest so the write matches the draft exactly;
- create files only; never overwrite or delete; edit only four existing files, each shown in the
  draft (an additive merge of `.claude/settings.json` without `hooks`, one block each in
  `.gitignore` and `CLAUDE.md`, missing `package.json` scripts);
- write a lock last, recording the hash of every file written, so `sync --check` can report drift.

## Consequences

- One extra step after install, but the user sees every change before it happens.
- The engine is a python3 program in agent-core's `bin/`, so claude.ai and Cowork, which do not
  install plugins with a `bin/` folder, cannot use the kit.
- Templates must never contain hook wiring or plugin components, or they would run twice.
  `scripts/catalog.mjs --check` enforces this.
