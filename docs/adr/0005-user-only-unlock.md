# 5. `.env` edits and production writes open only through a user-run, expiring unlock

- Status: accepted
- Date: 2026-09-26

## Context

Two actions need a person's decision every time: changing secret values in `.env*` files, and
writing to the production database. A phrase typed in the chat ("I allow it") is not a decision
the hooks can trust: text in the conversation can come from a file Claude read. Leaving both always
open, or always closed, fails either safety or the rare real incident.

## Decision

- Two targets, locked by default: `env` (20 minutes) and `db` (15 minutes). Only the user opens
  one, by running `scripts/ops/unlock.sh <target> [minutes]` with `!` in Claude Code or in their own
  terminal. The `unlock` package script is an alias of the same file.
- The unlock writes `.claude/state/unlock/<target>` holding its expiry; the hooks accept only a file
  written that way (private mode, not a link, not tracked, not expired). `status` and `off` manage
  it.
- safety-check refuses the agent running the unlock or touching `.claude/state/unlock/` by every
  route it can read; the Bash sandbox (when enabled) refuses writes there at the operating-system
  level.
- While `env` is open, Claude changes values only through `scripts/env/set.sh` (value on stdin,
  backup, key-only audit log). `scripts/env/show.sh` always lists keys with secrets masked. db-guard
  lets one read-only statement through at any time.

## Consequences

- A secret value never needs to appear in the transcript, and a production write always needs a
  fresh, deliberate act by a person.
- The hooks read text, so the limits are documented honestly in [docs/unlock.md](../unlock.md);
  the read-only database server mode and the sandbox are the layers below.
