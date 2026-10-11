### Rust + Axum service (agent-be-axum)

- Rules: `AGENTS.md`; traps: `.claude/anti-patterns/INDEX.md`. Review with the
  `agent-be-axum:reviewer` subagent for standards and `agent-core:spec-reviewer` against the spec.
- A merged migration and the generated `.sqlx/` and `openapi.json` are refused by the guards: a
  schema change is a new `sqlx migrate add` file; regenerate the rest with `cargo sqlx prepare` and
  `cargo run --locked --quiet --bin openapi`.
