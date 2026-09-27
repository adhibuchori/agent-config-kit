# 3. One per-repo config file, `.claude/agent-config.json`, which is also the opt-in

- Status: accepted
- Date: 2026-09-26

## Context

A plugin's hook matchers and scripts are the same for every repo, but repos differ: which branches
are protected, which paths are generated, where migrations live, which wrapper commands a team
uses. Users cannot edit an installed plugin. Separately, Anthropic's plugin review flags
plugins whose hooks act in every project: a hook must stay silent unless the project asked for it.

## Decision

- Hooks read their per-repo settings from `.claude/agent-config.json`. Every key is optional; a key
  replaces its default whole; a malformed key falls back to the default with a warning. The
  template `.claude/agent-config.example.json` documents every key.
- In plugin mode every hook exits 0 before reading its input unless the project has
  `.claude/agent-config.json` or `.claude/agent-config-kit.lock`. Either file opts the repo in.
- Settings that are not hook settings (permissions, sandbox) stay in `.claude/settings.json`.

## Consequences

- Installing the plugins changes nothing in a repo until it opts in.
- One file to review for "why did the hook allow this here": the diff of `agent-config.json`.
  `.claude/settings.json` asks before Claude edits it.
- Matchers stay broad where a user would need to edit them (db-guard matches `mcp__.*` and filters
  by `dbWriteGuard.toolPattern`), at the cost of one short python3 run per MCP call.
