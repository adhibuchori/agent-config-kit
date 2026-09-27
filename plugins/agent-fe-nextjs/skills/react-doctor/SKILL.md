---
name: react-doctor
description: User-invoked React scan and triage (`/agent-fe-nextjs:react-doctor`). Runs the React Doctor CLI for lint, accessibility, bundle-size and architecture diagnostics, with its telemetry and lookups turned off. Uses the project's own installed CLI; without one it downloads the pinned react-doctor 0.9.14 from npm once, after the user agrees. Includes a regression check and a local triage workflow.
disable-model-invocation: true
---

# React Doctor

Scans React code for security, performance, correctness and architecture issues.

Adapted from React Doctor's own skill (version 1.2.0), Copyright (c) 2026 Million Software, Inc.,
under the Modified MIT License in [LICENSE](LICENSE), which also names the uses that need the
vendor's written permission. What changed here: the project's own CLI is preferred and the download
is pinned instead of `@latest`; the triage workflow in `references/triage.md` is written for this
repo and read locally, never fetched from the vendor's site at run time, so nothing outside the repo
changes what an agent is told; and scans keep their results local (below). An upgrade raises the pin
here, in both references, and in agent-fe-nextjs's `.github/workflows/react-doctor.yml` template
together, after reading the release notes; `/agent-fe-nextjs:sync` then brings the new pin to a repo
that installed the workflow.

## Keep scans local

By default a scan sends data to two services. Its diagnostics (rule, message and a scrubbed file
path) and repository metadata (repo name, commit, framework, React version, file count) go to the
vendor's score API, along with crash reports and usage telemetry. On a full scan, or when a
manifest changed, each dependency's name and version also goes to Socket.dev for a supply-chain
score. `--no-score` (alias `--no-telemetry`) turns off the score API, the share link, crash
reporting and telemetry; `--no-supply-chain` turns off the dependency lookup. Pass both on every
run unless the user has agreed to share that data. The report then carries no health score, so
compare diagnostics instead. Known-vulnerable dependencies are the quality gate's job
(the audit gate, `scripts/check/audit.ts` in the repo), not this scan's.

## Where the CLI comes from

This skill runs only when the user starts it (`disable-model-invocation`), because it may download
code.

1. **The project's own copy first.** When `node_modules/.bin/react-doctor` exists, use it: nothing
   is downloaded. Print its version once (`node_modules/.bin/react-doctor --version`) and say so
   when it is not 0.9.14, the version these instructions were written for.
2. **Otherwise, the pinned download, after a yes.** `bunx react-doctor@0.9.14` fetches that exact
   version from the npm registry the first time and caches it. Before the first run, tell the user
   exactly that and wait for their yes; on a no, stop and suggest
   `bun add -d react-doctor@0.9.14`, which puts the CLI in the project. Never `@latest`, never an
   unversioned package.

Each shell call starts fresh, so every command below starts by choosing the CLI:

```bash
RD=(bunx react-doctor@0.9.14); [ -x node_modules/.bin/react-doctor ] && RD=(node_modules/.bin/react-doctor)
```

## Command

Always the chosen CLI with both flags above.

```bash
"${RD[@]}" --no-score --no-supply-chain --verbose --scope changed   # after React changes
"${RD[@]}" --no-score --no-supply-chain --verbose                   # general cleanup
"${RD[@]}" --no-score --no-supply-chain design --verbose            # UI design audit
```

- After React code changes, a diagnostic the base branch did not have is a regression: fix it
  before committing.
- A general cleanup scans the full scope. Fix errors first, then warnings.
- The design audit runs only the design-tagged composition, typography, interaction,
  accessibility and motion rules, including those that stay opt-in in a general scan.
- Dead code is not reported here: the repo's `doctor.config.json`
  sets `deadCode: false`, because Knip owns unused files, exports and dependencies
  (the dead-code rule, `.claude/rules/typescript/dead-code.md`).

| Flag                | Purpose                                                          |
| ------------------- | ---------------------------------------------------------------- |
| `.`                 | Scan current directory                                           |
| `--no-score`        | Skip the score API, share link, crash reports and telemetry      |
| `--no-supply-chain` | Skip the dependency lookup at Socket.dev                         |
| `--verbose`         | Show affected files and line numbers per rule                    |
| `--scope changed`   | Only report issues introduced vs the base branch (default: full) |
| `--scope lines`     | Only report issues on the changed lines                          |
| `--json`            | One structured JSON report, for comparing runs                   |
| `design`            | Run only the focused UI design diagnostics                       |

## /agent-fe-nextjs:react-doctor — local triage

When the user asks for a full triage or cleanup pass rather than a regression check, follow
[references/triage.md](references/triage.md). (`/agent-fe-nextjs:react-doctor` is this skill;
`/doctor` is Claude Code's own health check.) Guidance for a
single rule comes from `"${RD[@]}" --no-score rules explain <rule>`; do not fetch rule prompts
from the web.

## Configuring or explaining rules

When the user wants to understand a rule, disagrees with one, or wants to tune which rules run
rather than fix code, read [references/explain.md](references/explain.md) and follow it.
