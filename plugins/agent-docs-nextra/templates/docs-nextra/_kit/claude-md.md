### Docs site (agent-docs-nextra)

- A static Nextra export: nothing may need a request-time server. Rules:
  `.claude/rules/docs-site/content.md`; known traps: `.claude/anti-patterns/INDEX.md`, read before
  touching the `nextra` versions or the dev and build scripts.
- Generated pages change at their source, then the generator runs again; the `generated-guard` hook
  refuses hand edits to `generatedPaths` (`.claude/agent-config.json`).
- `bun run build`, never `bun build`. Before calling a task done: `bash scripts/check/gates.sh`.
- `agent-docs-nextra:seo-validator` and `agent-docs-nextra:security-guard` review metadata and
  security changes, and only report.
