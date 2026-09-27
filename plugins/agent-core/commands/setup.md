---
description: Install agent-core's permissions, rules, check scripts and the unlock and .env helpers into this repo, after a dry run you approve
argument-hint: "[--answer id=value ...]"
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Bash(git status:*), Bash(agent-setup questions:*), Bash(agent-setup plan:*), Bash(agent-sync check:*)
---

# /agent-core:setup — Set Up agent-core In This Repo

A plugin cannot carry permissions, `.claude/rules/`, check scripts or the unlock and `.env` helpers,
so this command installs them into the repo: it explores, asks one question at a time, shows the
exact draft, and writes only after the user replies **go**. It never overwrites a file, never
deletes one, and edits only four existing files, each shown in the draft: an additive merge of
`.claude/settings.json`, one block in `.gitignore`, one block in `CLAUDE.md`, and a missing
`unlock` script in `package.json`. The lock `.claude/agent-config-kit.lock` is written last; its
presence turns the kit's hooks on in this repo.

A stack plugin's own setup (for example `/agent-fe-nextjs:setup`) includes this one: when the user
has a stack plugin installed, suggest running that instead, once.

**Arguments:** $ARGUMENTS (pre-answered questions, `--answer id=value`)

The engine runs as `agent-setup`, a program in agent-core's `bin/`. If `command -v agent-setup`
finds nothing, stop: agent-core is not enabled in this session (claude.ai and Cowork do not install
plugins that have a `bin/` folder). Ask the user to enable it (`/plugin`) and to restart the
session.

## Step 1: Explore (read-only)

Read what setup would touch, and note what you find:

- `package.json` and the lockfile (`bun.lock`, `bun.lockb`, `pnpm-lock.yaml`, `yarn.lock`,
  `package-lock.json`): the package manager decides how the user types `unlock`
  (`docs/unlock.md` once installed). No `package.json` means no alias: unlock is then
  `./scripts/ops/unlock.sh`. Also `tsconfig.json` and `pyproject.toml` (the `language` question).
- `.claude/settings.json` and `.claude/settings.local.json`: any `hooks` wiring there that runs a
  script agent-core also runs (safety-check.sh, db-guard.sh, ...) is **double wiring**; each such
  hook would run twice. Setup never edits `hooks`; the draft warns, and the fix is to remove those
  entries from the project settings.
- `CLAUDE.md`, `.gitignore`, `.mcp.json`, `.claude/agent-config.json`.
- `git status --short`: if the tree is dirty, say so. Setup's writes are easier to review on a clean
  tree.

## Step 2: Ask, one question at a time

```bash
agent-setup questions --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack common --json
```

For each question, in order: ask it alone, give the choices, and give the **recommended** answer
with one line of why, adjusted by what Step 1 found and citing the evidence (for example "you have
`pyproject.toml` and no `package.json`, so python"). Accept "ok" for the recommended answer. Wait
for the reply before asking the next question. Skip a question already answered in the arguments.

## Step 3: Draft

```bash
agent-setup plan --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack common --project "$PWD" --answer <id>=<value> ...
```

Show its output verbatim: every create, same, keep, seed, merge, conflict, block, alias, warn and
lock line, and the digest. Its first line names the project folder (`project .` when the shell is at
the repo root): if an earlier `cd` left the shell elsewhere, `cd` back to the root and plan again. Explain any `conflict` or `warn` line in one sentence. End with:
"Reply **go** to write exactly this."

## Step 4: Write only on "go"

On **go**, and only then:

```bash
agent-setup apply --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack common --project "$PWD" --answer <id>=<value> ... --digest <digest from step 3>
```

Use the same answers as Step 3. `apply` is deliberately left out of `allowed-tools`, so the user's
permission prompt is a second, independent confirmation. Any other reply means nothing is written.
Exit 3 means the project changed since the draft: show a new plan and ask again.

## Step 5: Verify

```bash
agent-sync check --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack common --project "$PWD"
```

Report the result (exit 0 is in sync; 4 means double wiring is still there). Remind the user to
commit the new files and `.claude/agent-config-kit.lock`: the lock is what turns the hooks on for
teammates. Point them at `docs/unlock.md` for `unlock env` and `unlock db`.
