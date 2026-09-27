### Next.js app (agent-fe-nextjs)

- Rules in `.claude/rules/` load with a matching file; traps: `.claude/anti-patterns/INDEX.md`.
- Generated output changes at its source; `generated-guard` refuses hand edits to `generatedPaths`.
- `bun run test` / `bun run build`, never `bun test` / `bun build`. Before calling a task done:
  `bash scripts/check/gates.sh`.
- `agent-fe-nextjs:reviewer`, `:i18n-guard` and `:seo-validator` review a diff and only report.
