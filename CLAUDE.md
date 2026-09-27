# agent-config-kit (maintainer notes)

A Claude Code plugin marketplace: eight plugins under `plugins/`, reusable CI under `.github/` and
`actions/`, docs under `docs/`. Terms mean what [CONTEXT.md](CONTEXT.md) says.

## Invariants (CI enforces each one)

- Every component (hook, command, agent, skill) appears in its plugin, in the README catalogs, in
  `docs/catalog.json` (how to use, why it helps, the Indonesian texts), on a page
  `docs/<plugin>/<name>.md` with the fixed headings, and every command in
  `plugins/agent-core/commands/help.md`. After adding or renaming one: `node scripts/catalog.mjs`.
- A command that installs files, commits, pushes, merges or posts to GitHub, and a skill that may
  download code, sets `disable-model-invocation: true`. Template permissions allow named scripts
  only, never a bare `bun run`, `uv run`, `npx` or `docker compose`.
- After touching any manifest, `hooks.json` or component frontmatter: `claude plugin validate
  --strict .` and on each changed `plugins/<p>`. Never put a version in `marketplace.json`.
- A change under `plugins/<p>/` bumps that plugin's `version` in `plugin.json` and adds a
  `### <p> <version>` entry to `CHANGELOG.md` (`node scripts/version-sync.mjs --check --base main`).
- Every `plugins/*/scripts/lib.sh` is an exact copy of agent-core's. Hooks: bash 3.2, `shellcheck -x -S
  style` clean, block only with exit 2 and a reason on stderr, stay silent without the opt-in, no
  network and no downloads.
- Templates never contain `package.json`, `.gitignore`, a real `CLAUDE.md`/`AGENTS.md` (use
  `*.starter`), `.claude/hooks|commands|agents|skills/`, or a `hooks` key in `settings.json`.
- Workflows: pull-request events and `workflow_call` only (one exception, named in
  `scripts/workflow-policy.py` and ADR 0004: docs-nextra's `changelog.yaml` also takes
  `repository_dispatch`). No `push:`, `schedule:`, `issue_comment` or Dependabot.
  Every `uses:` pinned to a full SHA with `# vX.Y.Z`; `contents: read`; `persist-credentials:
  false`; no `secrets: inherit`; no event data in `${{ }}` inside `run:`.
- `README.md` and `README.id.md` change together in the same pull request.
- Contributions are leak-free: no real hostnames, tokens, emails, product names or private repo
  names in code, fixtures, docs or commit messages.

## Before you open a pull request

`bats -r tests/`, `node scripts/catalog.mjs --check`, `node scripts/version-sync.mjs --check`,
`markdownlint-cli2` (its globs cover docs, commands, agents and skills) and
`lychee --offline --hidden` on changed docs. A new guard rule gets a probe that must block and one
that must pass. Every `.json` file is strict JSON (`jq empty`); notes go in Markdown next to it.
