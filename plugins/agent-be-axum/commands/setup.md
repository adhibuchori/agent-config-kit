---
description: Install agent-be-axum's backend rules, anti-patterns, service skeleton, gate scripts, lint and test config and pull-request CI into this Rust + Axum service, after a dry run you approve
argument-hint: "[--answer id=value ...]"
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Bash(git status:*), Bash(git branch --list:*), Bash(command -v agent-setup), Bash(agent-setup questions:*), Bash(agent-setup plan:*), Bash(agent-sync check:*), Bash(cargo --version), Bash(rustc --version)
---

# Set up agent-be-axum in this repo

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
(`/plugin install agent-core@agent-config-kit`), then run `/agent-be-axum:setup` again. It needs
python3 3.8 or newer.

## 1. Explore (read-only)

Read what setup would touch, and note what you find, with the file as evidence:

- `Cargo.toml` (package and library names, edition, `rust-version`, `[lints]`,
  `[profile.release]`), `Cargo.lock`, `rust-toolchain.toml`, `.cargo/config.toml`, `migrations/`,
  `.sqlx/`, `openapi.json`, `src/main.rs` and `src/lib.rs`. Note which exist: the draft keeps each
  one and reports it as `keep`; the lint tables for an existing `Cargo.toml` are a by-hand snippet.
- `cargo --version` and `rustc --version`, only to report the toolchain; setup installs no tool.
- `.claude/settings.json` and `.claude/settings.local.json`: a `hooks` key that runs
  `migration-guard.sh` or `generated-guard.sh`, or any `.claude/hooks/*.sh` from a copied
  template. With the plugins enabled, each of those runs twice (double wiring); setup never edits
  `hooks`, so the user removes those entries.
- `CLAUDE.md` and `AGENTS.md`. Each is created from the plugin's starter only where it is absent.
  If `AGENTS.md` already exists, say so: the `agent-be-axum:reviewer` subagent cites the starter's
  rule numbers and falls back to whatever the existing file defines.
- `.gitignore`, and `.claude/agent-config.json` (does it set `generatedPaths` or
  `appendOnlyMigrationsDirs`?).
- `.github/workflows/`, `.github/PULL_REQUEST_TEMPLATE/`, and `git branch --list dev prod` to see
  whether the dev → prod flow exists.
- `.claude/agent-config-kit.lock`: if it already lists `agent-be-axum`, stop and point the user at
  `/agent-be-axum:sync`.
- `git status --short`. If the tree is dirty, say so, and suggest committing first so the setup lands
  as a change of its own.

The draft seeds a service skeleton (`src/`, `tests/`, `openapi.json`) file by file, only where a
file is missing. In a crate that already has code, say which seeded files would land next to it:
they are not wired into an existing `lib.rs`, and the tests name the library `service`. If the repo
is not a Rust crate at all, say what you found and ask whether to go on.

## 2. Ask, one question at a time

Run:

```bash
agent-setup questions --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack be-axum --json
```

The list starts with agent-core's questions when this repo has no agent-core setup yet; that layer is
planned in the same draft. For each question the arguments did not answer:

- ask it on its own, with its choices;
- give the **recommended** answer and one line of why, adjusted by what step 1 found: cite the file
  (for example, no `dev` or `prod` branch exists, so `pr-templates` is probably no);
- accept "ok" as the recommended answer, and wait for the reply before the next question.

For agent-core's `language` question, recommend `rust` when it is a choice.

## 3. Draft

Run `agent-setup plan` with every answer:

```bash
agent-setup plan --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack be-axum --answer <id>=<value> ...
```

Show its output verbatim: every create, same, keep, seed, merge, conflict, block, alias, by-hand,
warn and lock line, and the digest. Below it, add at most three lines on what matters here (a
`keep` of a file the user may want to compare, a `conflict`, a `warn` about double wiring). End
with: "Reply **go** to write exactly this."

## 4. Write only on "go"

On **go**, run `agent-setup apply` with the same answers and the digest from step 3:

```bash
agent-setup apply --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack be-axum --answer <id>=<value> ... --digest sha256:<hex>
```

`apply` is left out of this command's allowed tools on purpose, so the user's permission prompt is a
second, independent confirmation. Any reply other than **go** writes nothing. If `apply` exits 3, the
repo changed since the draft: go back to step 3 and show the new plan.

## 5. Verify and hand over

Run:

```bash
agent-sync check --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack be-axum
```

Report its exit code and findings (0 means in sync). Then prove the generated-output guard on this
repo's spec:

```bash
printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"openapi.json"}}' \
  | bash "${CLAUDE_PLUGIN_ROOT}/scripts/generated-guard.sh"; echo "exit=$?"
```

Expect `exit=2` and a `[generated-guard] BLOCKED` line; nothing is written, the hook only reads the
payload. `exit=0` means `generatedPaths` no longer lists `openapi.json`: show the user
`.claude/agent-config.json` and let them fix it.

Then tell the user, briefly:

- Commit the new files together with `.claude/agent-config-kit.lock`: the lock is what turns the hooks
  on for everyone who clones the repo.
- By hand, once: a new repo got `Cargo.toml` from the starter, so run `cargo generate-lockfile` and
  commit `Cargo.lock` (every gate passes `--locked`). An existing `Cargo.toml` takes the block the
  draft's `by-hand` line names. Then `git config core.hooksPath .githooks`, so each commit runs the
  gates.
- The gates call tools the machine must have; setup installs none of them. A person installs the
  pinned versions: the toolchain `rust-toolchain.toml` names (with clippy, rustfmt and llvm-tools),
  cargo-llvm-cov 0.9.1 and cargo-nextest 0.9.148, Node 20 or newer, python3 and gitleaks. CI adds
  cargo-deny 0.20.2 and sqlx-cli 0.9.0.
- The database tier needs PostgreSQL 18 at the `DATABASE_URL` in `.env.ci.example`, as a role that
  may create databases.
- Before the first release, set `PROBLEM_TYPE_BASE` in `src/platform/error.rs` to an https URL the
  team owns and regenerate `openapi.json`; production refuses to start on the placeholder.
- Placeholders left to fill: the project name in `CLAUDE.md` and the description in `Cargo.toml`,
  the Compliance Status table at the top of `AGENTS.md` (fill it before relying on any rule), the
  handle in `.github/CODEOWNERS`, and `<client-repo>` in `.github/PULL_REQUEST_TEMPLATE/promotion.md`.
- The pull-request gate (`.github/workflows/quality-gate.yml`) installs once a plugin release pins
  it to a real commit; until then the draft holds it back with a `warn` line.
