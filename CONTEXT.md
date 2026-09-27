# Glossary

The words this repository uses, and what each one means here. The README, the plugin READMEs, the
docs pages and the commands all use these terms the same way. When a word below has an "Avoid" list,
do not use those words for this idea: they mean something else, or they are vague.

## Plugin

A folder under `plugins/` that Claude Code installs from this marketplace. It ships hooks, commands,
agents, skills and templates. Its name follows `agent-<role>-<framework>` and never changes after
1.0.0. **agent-core** is the plugin every other plugin depends on.

_Avoid:_ extension, package, add-on (except for the two optional plugins, agent-fe-threejs and
agent-deploy, which the docs call add-ons).

## Stack

The kind of repo a plugin is for, such as a Next.js app or a FastAPI service. Each plugin has a
stack id: the plugin name without `agent-` (`fe-nextjs`, `be-hono`), and `common` for agent-core.
One repo has one primary stack plugin, plus agent-core and any add-ons.

_Avoid:_ template (a template is a file, see below), flavour, preset.

## Hook

A script Claude Code runs by itself at a fixed moment: before a tool runs (PreToolUse), after it
ran (PostToolUse), when you send a prompt (UserPromptSubmit), or when a session starts
(SessionStart). The kit's hooks read the event as JSON on stdin. There are two kinds: guards and
feedback hooks.

_Avoid:_ git hook (that is `.husky/pre-commit`, which runs gates), trigger, listener.

## Guard

A PreToolUse hook that can refuse a tool call. It refuses with exit code 2 and a reason on stderr,
which Claude reads. Only exit 2 blocks: a crash or a timeout would let the call through, so every
guard **fails closed** (it refuses what it cannot check). The guards are safety-check, db-guard,
mcp-guard, generated-guard and migration-guard.

_Avoid:_ filter, blocker, validator (a validator is a review agent).

## Feedback hook

A hook that only adds context for Claude and never blocks: post-edit, post-commit, prompt-intent
and session-start. Every feedback hook **fails open**: if it cannot do its job, it says nothing and
exits 0.

_Avoid:_ warning hook, soft guard.

## Gate

A check that decides whether a change may land: the pre-commit gate (`bash scripts/check/gates.sh`,
from `scripts/check/gates.list`) and the CI quality gate (a reusable workflow that runs on pull
requests). A gate runs your project's own tools; a guard runs inside Claude Code.

_Avoid:_ hook (for the pre-commit gate), pipeline, linter (a linter is one of the gates).

## Rule

A Markdown file under `.claude/rules/` that Claude Code loads as instructions. Most rules have a
`paths:` list, so they load only while Claude works on a matching file. Rules are text: a gate or a
guard is what enforces them.

_Avoid:_ policy, guideline, lint rule (that is an oxlint or ruff setting).

## Anti-pattern

A short file under `.claude/anti-patterns/` that records one trap: the symptom, the cause, the fix
and the signal that tells you it is back. `.claude/anti-patterns/INDEX.md` lists them. `/agent-core:rca`
reads the index first, and `/agent-core:learn-session` adds new ones.

_Avoid:_ gotcha, lesson, note.

## Template

A file a plugin ships under `plugins/<plugin>/templates/<stack>/` for setup to install into your
repo. The folder mirrors where each file lands. `_kit/` holds setup's own data and is never
installed.

_Avoid:_ starter (a `*.starter` file is one special kind of template, see Seeded file), boilerplate.
The four `*-agent-config` repos are called **template repos**.

## Setup

`/<plugin>:setup`: the command that installs a plugin's templates into your repo. It explores the
repo, asks one question at a time with a recommended answer, shows a dry run (the **draft**), and
writes only when you reply **go**. It never overwrites or deletes a file. It exists because a plugin
cannot ship permissions or `.claude/rules/`.

_Avoid:_ install (installing is `/plugin install`), init, bootstrap.

## Sync

`/<plugin>:sync`: compares your repo with what setup installed. `--check` only reports (and exits
non-zero on drift or double wiring). Without `--check` it shows a draft and, on **go**, brings
unchanged files up to date. It never touches a file you edited.

_Avoid:_ update (updating the plugin itself is `claude plugin update`), upgrade, refresh.

## Drift

Any difference between your repo and the lock: a managed file that is missing, edited or lost its
exec bit; a template that changed upstream; a settings entry, managed block or package script that
is gone. `agent-sync check` lists each one as a finding and exits 1.

_Avoid:_ diff, out of date (drift includes files you changed, not only files the kit changed).

## Lock

`.claude/agent-config-kit.lock`: a JSON file setup writes last. It records which plugins are set up,
their versions, your answers, and the SHA-256 of every file setup wrote. `agent-sync check` compares
the repo with it. Commit it: its presence is also the opt-in.

_Avoid:_ lockfile (that is `bun.lock` or `package-lock.json`), unlock (a different mechanism, below).

## Opt-in

What turns the kit's hooks on in one repo. An installed plugin's hooks stay silent (exit 0 before
reading anything) unless the repo has `.claude/agent-config-kit.lock` or `.claude/agent-config.json`.
So installing the plugins never changes a repo you have not set up.

_Avoid:_ enable (enabling is a plugin setting that applies to every repo), activate.

## Unlock

The temporary, user-only opening of one of two locks: `env` (Claude may change `.env*` values
through `scripts/env/set.sh`, 20 minutes by default) and `db` (SQL that writes may reach the
production database, 15 minutes by default). Only you run it, with `!` in front, for example
`! bun unlock env`. Claude is refused if it tries. It closes by itself. See [docs/unlock.md](docs/unlock.md).

_Avoid:_ permission, allow, "I allow it" in the chat (asking in the chat unlocks nothing).

## Managed block

The one section setup owns inside a file that is otherwise yours: a block between marker comments
in `CLAUDE.md` (under the heading `## Agent config kit`) and in `.gitignore`. Sync rewrites the
block and never touches the text outside it.

_Avoid:_ section, snippet (a snippet is text the draft asks you to add by hand).

## Seeded file

A file setup creates once and then hands to you, because you are expected to edit it: for example
`scripts/check/gates.list`, lint configs, and every `*.starter` file (installed without the
`.starter` suffix, such as `CLAUDE.md` and `AGENTS.md`). Sync never checks a seeded file.

_Avoid:_ default file, sample.

## Owned file

A managed file you took over with `agent-sync own <path>`. Sync stops checking it. `own --undo`
hands it back to the kit.

_Avoid:_ ignored file, forked file.

## Double wiring

The same hook script wired twice: once by the plugin, and once in your `.claude/settings.json`
(which happens when a repo was copied from a template repo). Each such hook would run twice.
`agent-sync check` reports it as `double-wired` and exits with bit 4 set; the fix is to delete that
entry from `.claude/settings.json`.

_Avoid:_ duplicate hook, conflict (a conflict is a settings value where yours and the kit's differ).
