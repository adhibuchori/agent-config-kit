# Out of scope

Ideas that were considered and deliberately left out, with the reason. Before you open a feature
request, check this list: a request for one of these needs a new argument, not the same one again.
If the reason below no longer holds, say why in the issue.

## Reading permission from the chat

A hook never accepts "I allow it" (or any phrase) as permission. Text in the conversation can come
from a file Claude read. A refused command is run by you with `!`; a locked target is opened with
the [unlock](../docs/unlock.md) command. See [ADR 0005](../docs/adr/0005-user-only-unlock.md).

## Substring-matching guards

Matching `push --force` or `.env` as plain text blocks harmless commands and misses real ones
(`git -C . push`, a wrapper, `bash -c`). safety-check parses commands the way a shell does and
refuses what it cannot resolve.

## Guards that fail open

A guard that lets a call through when python3 is missing, the input is malformed or a check hangs
is not a guard. Every guard fails closed; only the feedback hooks fail open.

## Scheduled CI, push-triggered CI and Dependabot

CI runs on pull requests only. See [ADR 0004](../docs/adr/0004-pull-request-only-ci.md).

## Setup that writes without a draft, or overwrites files

Setup always shows the full draft, writes only on **go**, never overwrites or deletes a file, and
edits only the four managed places. A "just do it" mode would remove the one moment you can see
what changes. See [ADR 0001](../docs/adr/0001-plugins-cannot-carry-permissions.md).

## A per-hook on/off switch inside the plugin

Claude Code enables and disables plugins as a whole. The kit narrows single rules through
`.claude/agent-config.json` (for example `"generatedPaths": []`) instead of adding its own switch
layer, which would be one more place for a guard to be silently off.

## claude.ai and Cowork

They do not install plugins that have a `bin/` folder, and the setup engine lives in agent-core's
`bin/`. The kit targets Claude Code (CLI and IDE extensions).

## Network access, telemetry or run-time downloads in hooks

Hooks, `bin/`, `libexec/` and hook scripts never open a connection or install anything
(`scripts/catalog.mjs --check` enforces it). Commands that need the network (GitHub, deploy checks)
run only when you start them.

## Vendoring third-party skills

Third-party skills are added by reference (a pinned install plus a lock of hashes), never copied into
this repository, so their licences and updates stay with their authors. agent-fe-nextjs's
`react-doctor` skill is adapted under its licence with the changes listed in the skill.

## Platform-specific deploy adapters

agent-deploy knows no hosting vendor. Your platform's commands live in your repo's
`.claude/OPERATIONS.md` § Deploys.

## A security boundary against a hostile agent

The hooks read command text; they are a guardrail against slips and injected instructions, not a
sandbox. The operating-system sandbox and the read-only database mode are the stronger layers, and
their limits are documented in [docs/unlock.md](../docs/unlock.md).

## Native Windows and WSL1

The hooks are bash 3.2+ scripts, and Claude Code's Bash sandbox supports macOS, Linux and WSL2 only.
