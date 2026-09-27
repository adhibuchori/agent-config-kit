---
description: Install agent-ai-fastapi's backend and Python rules, anti-patterns, pre-commit and gate config, pipeline example and pull-request CI into this FastAPI + uv repo, after a dry run you approve
argument-hint: "[--answer id=value ...]"
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Bash(git status:*), Bash(git branch --list:*), Bash(command -v agent-setup), Bash(agent-setup questions:*), Bash(agent-setup plan:*), Bash(agent-sync check:*)
---

# Set up agent-ai-fastapi in this repo

A plugin cannot carry permissions, rules or a repo's own scripts, so this command installs them as
files. Nothing is written until the user has seen the whole draft and replied **go**. Existing files
are never overwritten: the only edits to files that already exist are the managed merges the draft
lists (`.claude/settings.json`, one block each in `.gitignore` and `CLAUDE.md`, and the `unlock`
script in a `package.json` that already exists). `pyproject.toml` is never edited: the draft shows
its sections as a `by-hand` line.

Arguments: `$ARGUMENTS`. Each `--answer id=value` there answers that question in advance; ask only
the rest.

Every step runs in this order, and none is skipped. The engine is agent-core's `agent-setup`; the
templates path below is written out in full because the Bash tool does not export
`CLAUDE_PLUGIN_ROOT`.

## 0. Check the engine

Run `command -v agent-setup`. If it prints nothing, stop and tell the user: `agent-setup` ships in
agent-core, which this plugin depends on; install or enable it
(`/plugin install agent-core@agent-config-kit`), then run `/agent-ai-fastapi:setup` again. It needs
python3 3.8 or newer.

## 1. Explore (read-only)

Read what setup would touch, and note what you find, with the file as evidence:

- `pyproject.toml` and `uv.lock`. The gates, the permissions and the commit hook assume uv. Note
  which of the sections the gates read already exist (`[dependency-groups] dev`, `[tool.ruff]`,
  `[tool.mypy]`, `[tool.pytest.ini_options]`, `[tool.coverage.run]`, `[tool.coverage.report]`,
  `[tool.importlinter]`, `[tool.vulture]`, `[tool.deptry]`): the user merges the kit's versions by
  hand, so say which ones will need a decision. With no `pyproject.toml`, setup creates one from the
  plugin's starter.
- `package.json`. A Python repo usually has none; then no `unlock` alias is added, and the user runs
  `./scripts/ops/unlock.sh` directly. If one exists, agent-core adds the alias there.
- `.claude/settings.json` and `.claude/settings.local.json`: a `hooks` key that runs
  `migration-guard.sh`, or any `.claude/hooks/*.sh` from a copied template. With the plugins enabled,
  each of those runs twice (double wiring); setup never edits `hooks`, so the user removes those
  entries.
- `CLAUDE.md`, `AGENTS.md` and `SSOT.md`. Each is created from the plugin's starter only where it is
  absent. If `AGENTS.md` already exists, say so: the `agent-ai-fastapi:ai-reviewer` subagent cites
  the starter's rule numbers and falls back to whatever the existing file defines.
- `.gitignore`, `.pre-commit-config.yaml`, and `.claude/agent-config.json` (does it set
  `migrationsDirs`?).
- The stack's markers: `fastapi` in `pyproject.toml`, `src/app/`, `alembic.ini` and its
  `script_location`, the folders `alembic/versions`, `migrations/versions` and
  `src/app/db/migrations/versions`, `.github/workflows/` and `.github/PULL_REQUEST_TEMPLATE/`. Run
  `git branch --list dev prod` to see whether the dev → prod flow exists.
- `.claude/agent-config-kit.lock`: if it already lists `agent-ai-fastapi`, stop and point the user at
  `/agent-ai-fastapi:sync`. If it lists another primary stack (`agent-be-hono`,
  `agent-docs-nextra`, `agent-fe-nextjs` or `agent-fe-nextjs-static`), stop too: setup refuses,
  because a repo uses one primary stack.
- `git status --short`. If the tree is dirty, say so, and suggest committing first so the setup lands
  as a change of its own.

If `alembic.ini` puts its revisions outside the guard's default folders (`src/db/migrations`,
`drizzle`, `src/app/db/migrations/versions`, `alembic/versions`, `migrations/versions`), say so now:
the migration guard protects nothing there until step 5 fixes it. If the repo is not a FastAPI
service at all, say what you found and ask whether to go on.

## 2. Ask, one question at a time

Run:

```bash
agent-setup questions --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack ai-fastapi --json
```

The list starts with agent-core's questions when this repo has no agent-core setup yet; that layer is
planned in the same draft. For each question the arguments did not answer:

- ask it on its own, with its choices;
- give the **recommended** answer and one line of why, adjusted by what step 1 found: cite the file
  (for example, `alembic.ini` exists, so `pipeline` is probably yes; no `dev` or `prod` branch
  exists, so `pr-templates` is probably no);
- accept "ok" as the recommended answer, and wait for the reply before the next question.

agent-core's `language` question recommends `typescript` on its own, which is wrong here. Recommend
from the evidence instead: `pyproject.toml` with no `package.json` or `tsconfig.json` means
`python` (the Python type and dead-code rules); a repo that also holds TypeScript means `both`.

## 3. Draft

Run `agent-setup plan` with every answer:

```bash
agent-setup plan --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack ai-fastapi --answer <id>=<value> ...
```

Show its output verbatim: every create, same, keep, seed, merge, conflict, block, by-hand, note,
warn and lock line, and the digest. Below it, add at most three lines on what matters here (a
`keep` of a file the user may want to compare, a `conflict`, a `warn` about double wiring, the
`by-hand` sections for an existing `pyproject.toml`). End with: "Reply **go** to write exactly
this."

## 4. Write only on "go"

On **go**, run `agent-setup apply` with the same answers and the digest from step 3:

```bash
agent-setup apply --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack ai-fastapi --answer <id>=<value> ... --digest sha256:<hex>
```

`apply` is left out of this command's allowed tools on purpose, so the user's permission prompt is a
second, independent confirmation. Any reply other than **go** writes nothing. If `apply` exits 3, the
repo changed since the draft: go back to step 3 and show the new plan.

## 5. Verify and hand over

Run:

```bash
agent-sync check --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack ai-fastapi
```

Report its exit code and findings (0 means in sync). If the repo has a migrations folder, prove the
migration guard on it (the folder from step 1; `alembic/versions` below):

```bash
printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"alembic/versions/0000_probe.py"}}' \
  | bash "${CLAUDE_PLUGIN_ROOT}/scripts/migration-guard.sh"; echo "exit=$?"
```

Expect `exit=2` and a `[migration-guard] BLOCKED` line; nothing is written, the hook only reads the
payload. `exit=0` means that folder is not guarded (it does not exist, or it is not in
`migrationsDirs`). Show the user the fix and let them make it: a `.claude/agent-config.json` holding
`{"migrationsDirs": ["<folder>"]}` (the key replaces the default list whole). A repo without a
migrations folder has nothing to guard: the hook stays inert until one exists, so the pipeline
shape turns it on by its layout. To keep it off in a repo that has migrations, the same file holds
`{"migrationsDirs": []}`.

Then tell the user, briefly:

- Commit the new files together with `.claude/agent-config-kit.lock`: the lock is what turns the hooks
  on for everyone who clones the repo.
- `pyproject.toml`: if it existed, merge the sections from
  `${CLAUDE_PLUGIN_ROOT}/templates/ai-fastapi/_kit/snippets/pyproject.tools.toml` by hand (offer to
  show it), keeping their own `[project]` table. If setup created it, fill `name`, `description` and
  the dependencies. Either way, replace `app.modules.<example>` with a real module in the two
  import-linter contracts that name it, then run `uv lock && uv sync`.
- Commit that layer before `uv run pre-commit install`: until `src/` and `tests/` hold a first
  module, `lint-imports`, `vulture`, `deptry` and pytest at 100% coverage fail, so a hook installed
  first refuses the commit that adds the layer. The gates also need Node 20+ (`folder-shape.mjs`,
  `coverage-policy.mjs`) and gitleaks; setup installs none of them.
- Placeholders left to fill, in the files setup created: the project name, snapshot and port in
  `CLAUDE.md`, the Compliance Status table at the top of `AGENTS.md` (fill it before relying on any
  rule), and every `<...>` in `SSOT.md`.
- Only the user unlocks `.env*` files and production writes, from their own shell or with `!`:
  `./scripts/ops/unlock.sh env` (or `db`, `status`, `off`); `docs/unlock.md` explains both.
- With `pipeline=yes`, `.claude/examples/pipeline/README.md` lists what to adopt by hand.
- The pull-request gate (`.github/workflows/quality-gate.yml`, if installed) runs on every pull
  request into `dev`, `prod`, `main` or `master` once the repo is on GitHub.
