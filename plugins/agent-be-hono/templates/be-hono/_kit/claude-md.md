### Bun + Hono API (agent-be-hono)

- Rules: `AGENTS.md`, `.claude/rules/backend/`; traps: `.claude/anti-patterns/INDEX.md`.
- The `migration-guard` hook refuses hand edits to generated migrations: change the schema, then
  `bun run db:generate`. Review with the `agent-be-hono:reviewer` subagent.
