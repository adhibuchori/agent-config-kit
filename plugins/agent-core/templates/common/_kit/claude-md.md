### Guardrails and workflow (agent-core)

- The kit's hooks run here while `.claude/agent-config-kit.lock` exists. A hook refusal or a deny
  rule is never argued away: hand the command to the user to run with `!`.
- `.env*` files: list one with `bash scripts/env/show.sh <file>` (secrets masked); change a value
  with `scripts/env/set.sh <file> <KEY>` (value on stdin), which works only while the user has
  unlocked `env`. Only the user unlocks `env` or `db` (`docs/unlock.md`).
- Commit by pathspec (`git commit -- <paths>`); only `/agent-core:ship` stages everything.
- Flow: `/agent-core:plan` → `/agent-core:review` → `/agent-core:commit` →
  `/agent-core:create-pr` → `/agent-core:merge-pr`. `/agent-core:help` lists every command.
- `/agent-core:sync --check` reports drift from what setup installed.
