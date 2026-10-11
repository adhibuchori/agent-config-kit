---
description: Install agent-be-go's backend rules, anti-patterns, service skeleton, gate scripts, lint and test config and pull-request CI into this Go HTTP service on PostgreSQL, after a dry run you approve
argument-hint: "[--answer id=value ...]"
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Bash(git status:*), Bash(git branch --list:*), Bash(command -v agent-setup), Bash(agent-setup questions:*), Bash(agent-setup plan:*), Bash(agent-sync check:*), Bash(go version), Bash(golangci-lint version:*)
---

# Set up agent-be-go in this repo

A plugin cannot carry permissions, rules or a repo's own scripts, so this command installs them as
files. Nothing is written until the user has seen the whole draft and replied **go**. Existing files
are never overwritten: the only edits to files that already exist are the managed merges the draft
lists (`.claude/settings.json`, one block each in `.gitignore` and `CLAUDE.md`).

Arguments: `$ARGUMENTS`. Each `--answer id=value` there answers that question in advance; ask only
the rest.

Every step runs in this order, and none is skipped. The engine is agent-core's `agent-setup`; the
templates path below is written out in full because the Bash tool does not export
`CLAUDE_PLUGIN_ROOT`.

## 0. Check the engine

Run `command -v agent-setup`. If it prints nothing, stop and tell the user: `agent-setup` ships in
agent-core, which this plugin depends on; install or enable it
(`/plugin install agent-core@agent-config-kit`), then run `/agent-be-go:setup` again. It needs
python3 3.8 or newer.

## 1. Explore (read-only)

Read what setup would touch, and note what you find, with the file as evidence:

- `go.mod`: the module path, the `go` and `toolchain` lines, and whether it already requires
  `github.com/jackc/pgx/v5`, `github.com/pressly/goose/v3` or `github.com/getkin/kin-openapi`. The
  seeded Go files import `example.com/service`; note the real module path for step 5.
- Which of these exist: `api/openapi.yaml`, `sqlc.yaml`, `db/migrations/`, `db/queries/`,
  `cmd/api/main.go`, `internal/`. The draft keeps each existing file and reports it as `keep`.
- `go version` and `golangci-lint version`, only to report what is installed; setup installs no
  tool. The gates need Go 1.27 and golangci-lint v2.14.0; say so when they differ.
- `.claude/settings.json` and `.claude/settings.local.json`: a `hooks` key that runs
  `migration-guard.sh` or `generated-guard.sh` from a copied template. With the plugins enabled,
  each of those runs twice (double wiring); setup never edits `hooks`, so the user removes those
  entries.
- `CLAUDE.md` and `AGENTS.md`. Each is created from the plugin's starter only where it is absent.
  If `AGENTS.md` already exists, say so: the `agent-be-go:reviewer` subagent cites the starter's
  rule numbers and falls back to whatever the existing file defines.
- `.gitignore`, `.claude/agent-config.json`, `.github/workflows/`, `.github/PULL_REQUEST_TEMPLATE/`,
  and `git branch --list dev prod` to see whether the dev → prod flow exists.
- `.claude/agent-config-kit.lock`: if it already lists `agent-be-go`, stop and point the user at
  `/agent-be-go:sync`.
- `git status --short`. If the tree is dirty, say so, and suggest committing first so the setup lands
  as a change of its own.

If the repo is not a Go HTTP service at all, say what you found and ask whether to go on.

## 2. Ask, one question at a time

Run:

```bash
agent-setup questions --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack be-go --json
```

The list starts with agent-core's questions when this repo has no agent-core setup yet; that layer is
planned in the same draft. For each question the arguments did not answer:

- ask it on its own, with its choices;
- give the **recommended** answer and one line of why, adjusted by what step 1 found: cite the file
  (for example, `db/migrations/` holds goose files, so `migrations` is yes);
- accept "ok" as the recommended answer, and wait for the reply before the next question.

For agent-core's `language` question, recommend `go` when it is among the choices.

## 3. Draft

Run `agent-setup plan` with every answer:

```bash
agent-setup plan --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack be-go --answer <id>=<value> ...
```

Show its output verbatim: every create, same, keep, seed, merge, conflict, block, alias, by-hand,
warn and lock line, and the digest. Below it, add at most three lines on what matters here (a `keep`
of a file the user may want to compare, a `conflict`, a `warn` about double wiring). End with:
"Reply **go** to write exactly this."

## 4. Write only on "go"

On **go**, run `agent-setup apply` with the same answers and the digest from step 3:

```bash
agent-setup apply --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack be-go --answer <id>=<value> ... --digest sha256:<hex>
```

`apply` is left out of this command's allowed tools on purpose, so the user's permission prompt is a
second, independent confirmation. Any reply other than **go** writes nothing. If `apply` exits 3, the
repo changed since the draft: go back to step 3 and show the new plan.

## 5. Verify and hand over

Run:

```bash
agent-sync check --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack be-go
```

Report its exit code and findings (0 means in sync). Then tell the user, briefly:

- Commit the new files together with `.claude/agent-config-kit.lock`: the lock is what turns the
  hooks on for everyone who clones the repo.
- `go.mod`: a repo without one got the starter. A repo with one keeps it, and the draft's `by-hand`
  line names the snippet to merge (the `tool` lines and the dependency floors); then `go mod tidy`.
- The module path: the seeded files and `.golangci.yml` say `example.com/service`. Replace it with
  the module path from step 1 in `go.mod`, `.golangci.yml` and the seeded `.go` files, in one change.
- The problem-type base: set `apperr.TypeBase` in `internal/apperr/types.go` and
  `x-problem-type-base` in `api/openapi.yaml` to one https URI under a domain the team owns, before
  the first release. It never changes after that, and production refuses to start with the
  placeholder.
- The commit gate: `git config core.hooksPath .githooks` once per clone, so `.githooks/pre-commit`
  runs `scripts/check/gates.sh`.
- The tools the gates call: Go 1.27, golangci-lint v2.14.0 (the release binary, checked against its
  checksums file), gitleaks, Node 20 or newer, and a PostgreSQL 18 the tests reach as
  `.env.ci.example` says; `.claude/rules/backend/testing.md` has the three commands that prepare it.
  Setup installs none of them.
- Placeholders left to fill: the project name in `CLAUDE.md`, the Compliance status table at the top
  of `AGENTS.md`, and `@your-github-handle` in `.github/CODEOWNERS`.
- The language server: the official `gopls-lsp` plugin gives Claude gopls diagnostics after each
  edit; it needs gopls on `PATH`.
- The pull-request gate (`.github/workflows/quality-gate.yml`) runs once a plugin release pins it; the
  draft says so when it held the caller back.
- With `payload-encryption=yes`: the gates stay red, on purpose, until the four steps under
  "Wiring it in" in `.claude/rules/backend/go-payload.md` are done: the five `ENVELOPE_*` codes in
  `Registered()` and in `api/openapi.yaml`, the handshake operation with its exemption, the
  middleware in `NewRouter` and the edge in `main`, then the server and the registry regenerated.
