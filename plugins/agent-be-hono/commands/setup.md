---
description: Install agent-be-hono's backend rules, anti-patterns, gate scripts, lint and test config and pull-request CI into this Bun + Hono + Drizzle repo, after a dry run you approve
argument-hint: "[--answer id=value ...]"
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Bash(git status:*), Bash(git branch --list:*), Bash(command -v agent-setup), Bash(agent-setup questions:*), Bash(agent-setup plan:*), Bash(agent-sync check:*)
---

# Set up agent-be-hono in this repo

A plugin cannot carry permissions, rules or a repo's own scripts, so this command installs them as
files. Nothing is written until the user has seen the whole draft and replied **go**. Existing files
are never overwritten: the only edits to files that already exist are the managed merges the draft
lists (`.claude/settings.json`, one block each in `.gitignore` and `CLAUDE.md`, missing
`package.json` scripts).

Arguments: `$ARGUMENTS`. Each `--answer id=value` there answers that question in advance; ask only
the rest.

Every step runs in this order, and none is skipped. The engine is agent-core's `agent-setup`; the
templates path below is written out in full because the Bash tool does not export
`CLAUDE_PLUGIN_ROOT`.

## 0. Check the engine

Run `command -v agent-setup`. If it prints nothing, stop and tell the user: `agent-setup` ships in
agent-core, which this plugin depends on; install or enable it
(`/plugin install agent-core@agent-config-kit`), then run `/agent-be-hono:setup` again. It needs
python3 3.8 or newer.

## 1. Explore (read-only)

Read what setup would touch, and note what you find, with the file as evidence:

- `package.json` and the lockfile. `bun.lock` or `bun.lockb` is what the gate list, the package
  scripts and the permissions assume. Note which of the scripts the gates call already exist with a
  different value (`format`, `fl:ci`, `lint`, `type-check`, `test:coverage`, `db:generate`, the
  `check:*` scripts): the draft keeps those and reports each one as a `conflict`.
  `scripts/check/migrations.sh` runs `bun run db:generate`, so a repo whose generator script has
  another name needs a `db:generate` that runs it.
- `.claude/settings.json` and `.claude/settings.local.json`: a `hooks` key that runs
  `migration-guard.sh`, or any `.claude/hooks/*.sh` from a copied template. With the plugins enabled,
  each of those runs twice (double wiring); setup never edits `hooks`, so the user removes those
  entries.
- `CLAUDE.md`, `AGENTS.md` and `SSOT.md`. Each is created from the plugin's starter only where it is
  absent. If `AGENTS.md` already exists, say so: the `agent-be-hono:reviewer` subagent cites the
  starter's rule numbers and falls back to whatever the existing file defines.
- `.gitignore`, and `.claude/agent-config.json` (does it set `migrationsDirs`?).
- The stack's markers: `hono` and `drizzle-orm` in `package.json`, `drizzle.config.*` and the `out`
  folder it names, `src/db/schema/`, `src/db/migrations/`, `.github/workflows/`, and
  `.github/PULL_REQUEST_TEMPLATE/`. Run `git branch --list dev prod` to see whether the dev → prod
  flow exists.
- `.claude/agent-config-kit.lock`: if it already lists `agent-be-hono`, stop and point the user at
  `/agent-be-hono:sync`.
- `git status --short`. If the tree is dirty, say so, and suggest committing first so the setup lands
  as a change of its own.

If `drizzle.config.*` writes migrations outside the guard's default folders (`src/db/migrations`,
`drizzle`, `src/app/db/migrations/versions`, `alembic/versions`, `migrations/versions`), say so now:
the migration guard protects nothing there until step 5 fixes it. If the repo is not a Bun + Hono +
Drizzle API at all, say what you found and ask whether to go on.

## 2. Ask, one question at a time

Run:

```bash
agent-setup questions --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack be-hono --json
```

The list starts with agent-core's questions when this repo has no agent-core setup yet; that layer is
planned in the same draft. For each question the arguments did not answer:

- ask it on its own, with its choices;
- give the **recommended** answer and one line of why, adjusted by what step 1 found: cite the file
  (for example, no `dev` or `prod` branch exists, so `pr-templates` is probably no);
- accept "ok" as the recommended answer, and wait for the reply before the next question.

agent-core's `language` question decides whether `scripts/check/double-assertion.sh` is installed,
and this plugin's `gates.list` runs it: for a Bun + Hono repo, recommend `typescript`.

## 3. Draft

Run `agent-setup plan` with every answer:

```bash
agent-setup plan --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack be-hono --answer <id>=<value> ...
```

Show its output verbatim: every create, same, keep, seed, merge, conflict, block, alias, warn and lock
line, and the digest. Below it, add at most three lines on what matters here (a `keep` of a file the
user may want to compare, a `conflict`, a `warn` about double wiring). End with:
"Reply **go** to write exactly this."

## 4. Write only on "go"

On **go**, run `agent-setup apply` with the same answers and the digest from step 3:

```bash
agent-setup apply --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack be-hono --answer <id>=<value> ... --digest sha256:<hex>
```

`apply` is left out of this command's allowed tools on purpose, so the user's permission prompt is a
second, independent confirmation. Any reply other than **go** writes nothing. If `apply` exits 3, the
repo changed since the draft: go back to step 3 and show the new plan.

## 5. Verify and hand over

Run:

```bash
agent-sync check --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack be-hono
```

Report its exit code and findings (0 means in sync). Then prove the migration guard on this repo's
own migrations folder (the `out` folder from step 1; `src/db/migrations` below):

```bash
printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"src/db/migrations/0000_probe.sql"}}' \
  | bash "${CLAUDE_PLUGIN_ROOT}/scripts/migration-guard.sh"; echo "exit=$?"
```

Expect `exit=2` and a `[migration-guard] BLOCKED` line; nothing is written, the hook only reads the
payload. `exit=0` means that folder is not guarded (it does not exist, or it is not in
`migrationsDirs`). Show the user the fix and let them make it: a `.claude/agent-config.json` holding
`{"migrationsDirs": ["<folder>"]}` (the key replaces the default list whole).

Then tell the user, briefly:

- Commit the new files together with `.claude/agent-config-kit.lock`: the lock is what turns the hooks
  on for everyone who clones the repo.
- The gates call tools the repo must have:
  `bun add -d husky knip oxfmt oxlint oxlint-tsgolint typescript drizzle-kit`, and
  `"prepare": "husky"` in `package.json` so `.husky/pre-commit` runs `gates.sh`. Setup installs none
  of them. `bun run lint` passes `--type-aware`, which is what needs `oxlint-tsgolint`.
- Three checks refuse to pass on nothing, so fill them before the first commit of code:
  `scripts/check/constants.config.json` (one entry per shared vocabulary),
  `coveragePathIgnorePatterns` in `bunfig.toml` (each raw client file, with its reason above it), and
  `src/test/preload.ts`, copied from `.claude/test-preload.example.ts`.
- Placeholders left to fill, in the files setup created: the project name and ports in `CLAUDE.md`,
  the Compliance Status table at the top of `AGENTS.md` (fill it before relying on any rule), every
  `<...>` in `SSOT.md`, and `<frontend-repo>` in `.github/PULL_REQUEST_TEMPLATE/promotion.md`.
- The pull-request gate (`.github/workflows/quality-gate.yml`, if installed) runs on every pull
  request once the repo is on GitHub.
