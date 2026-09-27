# react-doctor

Skill · agent-fe-nextjs · `/agent-fe-nextjs:react-doctor` · you start it; Claude does not load it by itself · may download the pinned CLI once, after you agree · scan telemetry off by flags

## What it does

The `react-doctor` skill scans React code for security, performance, correctness, accessibility and
architecture issues with the React Doctor CLI, and works through a local triage of what it finds.
It uses your project's own copy of the CLI (`node_modules/.bin/react-doctor`) when there is one.
Without one, it asks before it downloads `react-doctor@0.9.14`, one pinned version, from the npm
registry. It is adapted from the vendor's own skill under its licence (see
[License](#license) below).

## When to reach for it

When you finish a feature or want to clean up React diagnostics, type:

```text
/agent-fe-nextjs:react-doctor
/agent-fe-nextjs:react-doctor triage everything on this branch
```

Claude never loads it on its own (`disable-model-invocation: true`), because a run may download
code. Every scan passes `--no-score --no-supply-chain` unless you agree to share data, so the
results stay on your machine.

**Not for:** known-vulnerable dependencies; the dependency audit in your gates
(`scripts/check/audit.ts`) covers those.

## Prerequisites

- bun, and either React Doctor in the project (`bun add -d react-doctor@0.9.14`, nothing is
  downloaded at scan time) or network access to the npm registry for the one-time download.

## Common questions

**Does it download anything?**
Only when your project has no `node_modules/.bin/react-doctor`. Then `bunx react-doctor@0.9.14`
fetches that exact version from npm once and caches it; Claude says so and waits for your yes
first.

**What would a scan send without those flags?**
Diagnostics and repository metadata to the vendor's score API, and dependency names and versions to
a supply-chain service. The flags turn both off.

**Is there a CI version?**
Setup's `react-doctor-ci` question installs an advisory pull-request workflow
([react-doctor.yml](react-doctor.workflow.md)); it never fails the check. It runs the vendor's action with its defaults, which report to the vendor's score service,
so setup recommends **no**.

## License

The skill's files are adapted from React Doctor and keep Million Software's Modified MIT License
(`plugins/agent-fe-nextjs/skills/react-doctor/LICENSE`). It adds two conditions to MIT: using the
files as training, fine-tuning or evaluation data for an AI model, or as input to a pipeline that
trains or improves one, and selling them as a hosted or paid service, both need the vendor's written
permission. The rest of the kit is MIT. That is why agent-fe-nextjs declares
`MIT AND LicenseRef-Million-Modified-MIT`.

## It's working if

- Before any download, Claude names the version it would fetch and waits for your yes, or it says
  it uses `node_modules/.bin/react-doctor`.
- Every scan command it shows carries `--no-score --no-supply-chain`, and the report lists
  diagnostics by rule and file without a share link or health score.

## Where it fits

Part of [agent-fe-nextjs](../../plugins/agent-fe-nextjs/README.md). Fix what it finds, then
[/agent-core:review](../agent-core/review.md) and [/agent-core:commit](../agent-core/commit.md).
