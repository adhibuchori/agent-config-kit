## What and why

<!-- The failure this prevents or fixes, then what changed. Link the issue: Fixes #123. -->

## Checklist

- [ ] **Version bumped** in `plugins/<plugin>/.claude-plugin/plugin.json` for every plugin this
      changes (users get an update only when the version moves). Never in `marketplace.json`.
- [ ] **CHANGELOG.md** has an entry under `## [Unreleased]`, in a `### <plugin> <new version>`
      subsection, with a `**Breaking:**` line if a user must act.
- [ ] **Tests**: a bats test proves the change, including the case that must fail (a guard that
      blocks, a check that refuses). `bats -r tests/` passes locally.
- [ ] **`claude plugin validate --strict`** passes on `.` and on each plugin changed.
- [ ] **`node scripts/catalog.mjs --check`** and **`node scripts/version-sync.mjs --check`** pass
      (a new component has a docs page under `docs/<plugin>/` and a line in
      `/agent-core:help`).
- [ ] **Shell**: `shellcheck -x -S style` is clean and `/bin/bash -n` (bash 3.2) parses every
      script changed; hooks, `bin/` and `libexec/` download nothing.
- [ ] **Workflows** (only if `.github/`, `actions/` or a template workflow changed): pull-request
      events and `workflow_call` only, never `push:` or `schedule:`; every `uses:` pinned to a full
      SHA with a `# vX.Y.Z` comment; `permissions:` least privilege; `persist-credentials: false`;
      no `secrets: inherit`.
- [ ] **No private data**: no real hostnames, tokens, emails or product names in code, fixtures or
      docs.

## How to check it

<!-- Commands a reviewer can paste, and what they should print. -->
