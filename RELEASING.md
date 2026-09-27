# Releasing

How a maintainer ships plugins and the reusable workflows. Tags are described in
[ADR 0002](docs/adr/0002-plugin-tag-scheme.md).

## A plugin release

1. **Bump.** Raise `version` in `plugins/<p>/.claude-plugin/plugin.json` (SemVer: a removed
   command, setting or default, or a new required prerequisite, is a major bump). Never add a
   version to `marketplace.json`.
2. **Changelog.** Move the plugin's entries from `## [Unreleased]` into a new
   `## [X.Y.Z] - YYYY-MM-DD` release, under `### <p> <new version>`, with **Breaking:** lines where a
   user must act.
3. **Validate.**

   ```bash
   claude plugin validate --strict .
   claude plugin validate --strict plugins/<p>
   node scripts/catalog.mjs --check
   node scripts/version-sync.mjs --check --base <last release tag>
   bats -r tests/
   ```

4. **Dry-run the tag** (reads the version from `plugin.json`):

   ```bash
   claude plugin tag plugins/<p> --dry-run      # prints <p>--vX.Y.Z
   ```

5. **Merge** the release pull request (merge commit), then tag the merge commit:

   ```bash
   claude plugin tag plugins/<p> --push         # creates <p>--vX.Y.Z and pushes it to origin
   ```

Users receive the update when they run `claude plugin update <p>@agent-config-kit`.

## A workflow release (`vX.Y.Z` and `v1`)

The reusable workflows and `actions/` are released together with the repository release number.

1. Merge the changes to `.github/workflows/*-quality-gate.yml` and `actions/` first.
2. Tag that merge commit `vX.Y.Z` and publish a GitHub release for it; with immutable releases
   turned on, the tag and assets can no longer change.
3. Move `v1` to the same commit: `git tag -f v1 <sha>` and `git push -f origin v1` (the only tag
   that ever moves). Removing an input or changing a default needs `v2` instead.
4. **Update the callers in a later commit.** A caller template cannot pin the commit that contains
   it, so in a follow-up pull request replace the SHA in every
   `plugins/*/templates/**/.github/workflows/*.y*ml` caller with the `vX.Y.Z` commit (keep the
   `# vX.Y.Z` comment), bump each affected plugin, and release those plugins as above.
   `pinact run --check` and `version-sync.mjs --check` confirm the pins and comments.

1.0.0 shipped the callers with the placeholder `@0000000000000000000000000000000000000000 # v1.0.0`;
the 1.0.1 releases of the five stack plugins pinned them to the v1.0.0 commit. Setup never installs a caller that still holds the placeholder: the draft shows a
`warn … not installed` line and `sync --check` lists it as `held`, so a user never gets a gate
that fails every pull request. The release from step 4 is what installs the callers, through
`/<plugin>:sync`. Do not announce a marketplace whose callers still hold the placeholder.

## Before the first public release

Run the pre-publish checks once, locally:

- `scorecard --local .` (file-based checks), `gitleaks git .` and `gitleaks dir .`, a full-history
  scan for private terms, and a hidden-Unicode scan.
- A fresh-user test: add the marketplace from a local path in an isolated `CLAUDE_CONFIG_DIR`,
  install a stack plugin, run setup in a scratch repo, `sync --check`, and pipe a dangerous command
  to a hook.

## GitHub settings to enable

When the repository is created (and again when it becomes public, since some settings need that):

- A ruleset on `main`: block force pushes and deletion, require a pull request, require the
  **Self Test** status check.
- Tag protection for `v*.*.*` and `*--v*.*.*` (only `v1` may move).
- **Immutable releases.**
- **Private vulnerability reporting** (the link in [SECURITY.md](SECURITY.md) depends on it; it may
  only become available once the repository is public).
- Secret scanning with **push protection**.
- Actions: default workflow permissions read-only; Actions may not approve pull requests; squash
  merging turned off (the kit merges with merge commits).
