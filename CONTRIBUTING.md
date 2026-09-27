# Contributing

Thank you for helping. This repository is a Claude Code plugin marketplace; the terms it uses are
defined in [CONTEXT.md](CONTEXT.md), and the rules every change must keep are in
[CLAUDE.md](CLAUDE.md). By taking part you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

## Before you start

- For a new feature, open an issue first and check [.out-of-scope/](.out-of-scope/README.md).
- For a hook that refused something it should allow (or the reverse), use the **Hook bug** issue
  template, with the hook input JSON.
- For a vulnerability, follow [SECURITY.md](SECURITY.md) instead.

## Set up

You need Node 20+, bash (macOS `/bin/bash` 3.2 is the oldest supported), python3 3.8+, jq, git,
[bats-core](https://github.com/bats-core/bats-core) 1.5+, ShellCheck, and the Claude Code CLI.
For docs changes also `markdownlint-cli2` and `lychee`.

## Run the gate locally

These are the checks the Self Test workflow runs on your pull request:

```bash
claude plugin validate --strict .                     # the marketplace
for p in plugins/*/; do claude plugin validate --strict "$p"; done
node scripts/catalog.mjs --check                      # README catalog, docs pages, layout rules
node scripts/version-sync.mjs --check --base main     # versions, CHANGELOG, bump rules
git ls-files -z '*.sh' 'plugins/*/bin/*' | xargs -0 shellcheck -x -S style   # .shellcheckrc: source-path=SCRIPTDIR
bats -r tests/                                        # about 15 minutes; the hook probes are most of it
markdownlint-cli2                                     # the globs in .markdownlint-cli2.jsonc
lychee --offline --no-progress --hidden --exclude-path node_modules "**/*.md"   # .lycheeignore
gitleaks dir . --no-banner --redact                   # .gitleaks.toml extends .github/gitleaks.toml
```

The templates under `plugins/*/templates/` are not linted with markdownlint here: they become the
user's own files, written in each stack's house style, and their links are checked by lychee above
(`--hidden` reaches their `.claude/` folders).

On macOS, also run `/bin/bash -n` on every script you changed: CI proves bash 3.2 on macos-15.

## Making a change

1. **Plugins.** A change under `plugins/<p>/` bumps `version` in that plugin's `plugin.json` (not
   in `marketplace.json`) and adds an entry under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md),
   in a `### <p> <new version>` subsection. A change users must act on gets a **Breaking:** line.
2. **Components.** A new hook, command, agent or skill needs a description in its frontmatter, a
   page `docs/<p>/<name>.md` on the fixed template (copy a sibling page), and, for a command, a line
   in `plugins/agent-core/commands/help.md`. Then run `node scripts/catalog.mjs` to refresh the
   README catalogs.
3. **Hooks.** Keep them bash 3.2-compatible, block only with exit 2 and a reason on stderr, stay
   silent without the opt-in, and never use the network. Add a probe that must block and one that
   must pass, and prove the new probe fails when you disable your rule.
4. **Workflows.** Pull-request events and `workflow_call` only; every `uses:` pinned to a full SHA
   with a `# vX.Y.Z` comment; least-privilege permissions; `persist-credentials: false`.
5. **Docs.** Short sentences, one idea each, and the terms from CONTEXT.md. Every command you show
   must be one you ran. `README.md` and `README.id.md` change in the same pull request (CI checks
   it); if you cannot write Indonesian, say so in the pull request and a maintainer will help.
6. **No private data.** No real hostnames, tokens, emails, product names or private repository
   names anywhere, including fixtures and commit messages.

## Style

- Commit messages: lowercase `type: description` (`feat`, `fix`, `docs`, `refactor`, `test`,
  `chore`, `ci`, `perf`), imperative, no trailing period.
- Shell: `shellcheck -x -S style` clean, quote everything, `--` before outside arguments, no
  `eval` of input, no `cp -n`.
- JavaScript maintainer scripts: Node 20+, no dependencies, deterministic output.

## Pull requests

Fill in the pull request template's checklist. The one required status check is **Self Test**; it
passes only when every job in `.github/workflows/self-test.yml` passed.
