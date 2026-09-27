### FastAPI + LLM service (agent-ai-fastapi)

- Numbered rules: `AGENTS.md`; layers, providers and tests: `.claude/rules/backend/`. Known traps:
  `.claude/anti-patterns/INDEX.md`.
- Python tools run through `uv run`; mypy and pytest as `env -u PYTHONPATH uv run …`. Before calling
  a task done: `bash scripts/check/gates.sh`.
- Alembic revisions change only through `uv run alembic revision --autogenerate`: the
  `migration-guard` hook refuses hand edits under `migrationsDirs` (`.claude/agent-config.json`).
- Review a change with the `agent-ai-fastapi:ai-reviewer` subagent. No package.json here: the user
  unlocks with `! ./scripts/ops/unlock.sh env` (or `db`).
