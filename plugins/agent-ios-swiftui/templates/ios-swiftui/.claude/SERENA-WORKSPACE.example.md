# Serena: Shared Multi-Repo Workspace Scoping

> **List it in the CLAUDE.md "On-demand references" table; never `@`-import it.** An import loads
> the whole file into every session. This is a template, only relevant if you open this app and
> other repos (the backend whose spec it copies, for example) as one Serena project: copy it to
> `.claude/SERENA-WORKSPACE.md` and fill every `<placeholder>`. With a single repo, delete this
> file and its table row.

## What this is

On a machine configured for it, opening a session in any of your repos activates a **single shared
Serena project** covering `<N>` repos at once. Symbol tools (`find_symbol`,
`find_referencing_symbols`, `find_declaration`, `find_implementations`) then search all of them.

## This is machine-local configuration, not repo configuration

The shared workspace is enabled by two files that are **not in git** and belong to no repo:

- `~/.claude.json`: a local-scope MCP override per repo path, pointing Serena's `--project` at the
  workspace root instead of `.`
- `<workspace-root>/.serena/project.yml`: the project name, with each repo listed under
  `ls_workspace_folders`

The `.mcp.json` committed in every repo specifies `--project .`, so a fresh clone gets a single-repo
Serena. Do not "fix" `.mcp.json` by hard-coding the workspace path: it embeds one machine's paths.

## Swift in Serena

Serena reads Swift through sourcekit-lsp, which understands Swift packages natively. The code in
`Packages/AppCore` resolves exactly; the app target's files under `App/` get fallback settings, so a
symbol defined there may resolve less precisely. Install Anthropic's `swift-lsp` plugin for compile
diagnostics after each edit.

## Check which mode you are in, before your first path-scoped call

| Active project | `relative_path` resolves against | Prefix to use |
| --- | --- | --- |
| the workspace's name | the workspace root | `<path-to-repo>/...` |
| anything else | the repo you opened | none: plain repo-relative (`Packages/`) |

A wrong prefix fails loudly (`FileNotFoundError`, or a `ValueError` that lists every valid
workspace), so it is never mistaken for "the symbol does not exist".

## Default to narrow

Pass `relative_path` to scope every search you can (`Packages/AppCore/Sources`). Widen only for a
real cross-repo question, such as tracing an error code from the backend's registry to the app's
`ProblemCode`.
