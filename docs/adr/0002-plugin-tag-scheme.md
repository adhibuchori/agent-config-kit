# 2. Tag scheme: `<plugin>--vX.Y.Z` for plugins, `vX.Y.Z` and `v1` for workflows

- Status: accepted
- Date: 2026-09-26

## Context

One repository holds eight plugins that change at different speeds, plus five reusable workflows
that other repositories call by reference. Users receive a plugin update only when its version
changes. A workflow caller needs a reference that does not move under it, or one that follows a
major version on purpose.

## Decision

- `plugin.json` `version` is the single source of a plugin's version (SemVer). Marketplace entries
  carry no version.
- A plugin release is tagged `<plugin>--vX.Y.Z`, the format `claude plugin tag` creates and checks
  against `plugin.json`.
- The reusable workflows and composite actions are released together as `vX.Y.Z` (an immutable
  GitHub release) with a moving `v1` tag. Removing an input or changing a default is a major bump.
- Template callers pin the workflow by full commit SHA with a `# vX.Y.Z` comment.
- `scripts/version-sync.mjs --check --base <ref>` fails a pull request that changes a plugin without
  raising its version and adding a CHANGELOG entry.

## Consequences

- Plugins can ship independently; the CHANGELOG has one subsection per plugin per repo release.
- A caller's SHA cannot point at the commit that contains the caller itself, so the reusable
  workflows are committed and tagged first and the callers are updated in a later commit
  ([RELEASING.md](../../RELEASING.md)).
