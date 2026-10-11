### Go service (agent-be-go)

- Rules: `AGENTS.md`; traps: `.claude/anti-patterns/INDEX.md`. Review with the `agent-be-go:reviewer`
  subagent for standards and `agent-core:spec-reviewer` against the spec.
- Generated Go and merged migrations are refused by the guards: change `api/openapi.yaml` or
  `db/queries/`, then `bash scripts/check/generated.sh --write`; a schema change is a new migration
  file.
