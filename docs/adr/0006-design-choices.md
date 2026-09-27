# 6. The smaller design choices behind the guards, permissions, commands and templates

- Status: accepted
- Date: 2026-09-27

## Context

ADRs 1 to 5 record the decisions that are hard to reverse. Many smaller choices shape how the kit
behaves day to day. Without its reason, each one looks arbitrary, and a well-meant cleanup could
undo it. This record keeps those reasons in one place and names the file where each choice can be
checked today.

In the pointers below, `lib.sh` is `plugins/agent-core/scripts/lib.sh` (every plugin with a hook
ships an exact copy), and `templates/common/` is `plugins/agent-core/templates/common/`.

Choices the docs already explain are not repeated here: guards fail closed and feedback hooks fail
open ([CONTEXT.md](../../CONTEXT.md)); no hook reads permission from the chat
([ADR 5](0005-user-only-unlock.md)); which wrappers safety-check sees through
([safety-check](../agent-core/safety-check.md)); the `ask` rules on the guard files and the Bash
sandbox ([docs/unlock.md](../unlock.md)); narrow allow rules for scripts
([README, Security model](../../README.md#security-model)); and merge commits instead of squash
([merge-pr](../agent-core/merge-pr.md)).

## Decision

### Guards

- **One repo by default.** The hooks look above the repo only when `AGENT_WORKSPACE_ROOT` names a
  folder that holds several repos. Outside the repo and outside temp folders, a folder that holds a
  repo, or holds files some repo tracks, stays safe from `rm -r` whatever its name, so protection
  does not depend on a list of names. Where: `hook_root` and `protected_target` in `lib.sh`.
- **The opt-in sticks.** Under the plugin, a repo opts in with `.claude/agent-config.json` or
  `.claude/agent-config-kit.lock` ([ADR 3](0003-per-repo-config-file.md)). Once the plugin has
  seen either file in a project, it remembers that project: if both files disappear later, the
  hooks keep guarding with their defaults and say so. Deleting two files is something a slip, or an
  instruction hidden in a file Claude read, could do, so it is no off switch. Disabling the plugin
  for the project is. Where: `hook_gate` in `lib.sh`.
- **Only a missing python3 gets the plain-text fallback.** On a machine with no python3,
  safety-check judges each command with a few plain-text rules and tells Claude so, because
  refusing every shell command would stop all work there. A python3 that is installed but crashes,
  hangs or cannot read the input is a different case: the guard refuses the call. Where: the header
  of `plugins/agent-core/scripts/safety-check.sh`, and `hook_start` in `lib.sh`.
- **One deadline per guard.** Claude Code lets a call through when a hook times out after 10 s. So
  each guard has one 9 s deadline for its whole run: every slow step gets only the time that is
  left, and a guard still running at the deadline refuses the call and says it ran out of time.
  Separate caps per step could add up past the timeout. Where: `HOOK_DEADLINE`, `hook_cap` and
  `hook_exit` in `lib.sh`.
- **The hooks' own git never runs a program.** Every git a hook starts runs with
  `core.fsmonitor=false`. That setting is the one way a plain read such as `git rev-parse` or
  `git ls-files` runs a command from the repo's config. Where: the `git` function and
  `HOOK_PY_PRELUDE` in `lib.sh`.
- **The analyzer reaches python3 through a file descriptor.** The command analyzer is well over
  128 KiB, and Linux starts no program with one argument or environment string that long. So
  python3 reads the analyzer from descriptor 3, and `-c` holds only a small loader. Passed as one
  argument, it made safety-check refuse every command on Linux. Where: `analyze_command` in
  `lib.sh`, and the agent-core 1.0.2 entry in the [CHANGELOG](../../CHANGELOG.md).
- **A symlink is judged twice.** generated-guard and migration-guard check a written path both as
  named and as the file it points to, since the write lands there. A link they cannot follow is
  refused. Where: `hook_target` in `lib.sh`, and the headers of `generated-guard.sh` and
  `migration-guard.sh`.
- **Format and lint are one hook.** post-edit formats and then lints in one script, because hooks
  on the same event run in parallel, and a separate lint hook would race the formatter. Where:
  `plugins/agent-core/scripts/post-edit.sh`.
- **Alembic gets one rule.** safety-check refuses `alembic downgrade`, and only where an
  `alembic.ini` exists. Rules that depend on how several services share one schema belong in that
  project's own rules, not in a guard every repo runs. Where: the Alembic branch of the analyzer in
  `lib.sh`.
- **The unlock scripts find the repo from their own path.** `unlock.sh` and the `.env` helpers
  work out the repo root from where the script file lives, never from an environment variable the
  agent could set. `unlock.sh` also refuses to run through a symlink, a hard link or a copy, since
  a copy elsewhere would compute another repo's root ([ADR 5](0005-user-only-unlock.md)). Where:
  `templates/common/scripts/ops/unlock.sh` and `templates/common/scripts/env/envfile.py`.

### Permissions and MCP

- **The deny rules repeat the hook's branches.** `.claude/settings.json` denies `git push origin`
  to `dev`, `prod`, `main` and `master`, the same four branches as the hook's default
  `protectedBranches`. The overlap is on purpose. A permission rule matches how a command starts,
  so `git -C . push origin main` or a push inside `bash -c` slips past it; safety-check reads the
  command the way a shell does and catches both. The rule still holds when the hooks are off. A
  branch you add to `protectedBranches` is guarded by the hook only; add a matching deny rule if you
  want both layers. Where: `templates/common/.claude/settings.json`, and `HOOK_DEFAULTS` in
  `lib.sh`.
- **No allow rule writes files.** Every template's allow list holds named commands (and, in
  agent-core, `Read(**)`), never a `Write` or `Edit` rule, so every edit goes through Claude Code's
  normal permission prompt. Where: `plugins/*/templates/*/.claude/settings.json`.
- **Both database servers start read-only.** `db-dev` and `db-prod` both run with
  `--access-mode=restricted`. The `ask` rule on `mcp__db-prod__execute_sql` is not enough on its
  own: `bypassPermissions` mode skips `ask` rules, so the server's own mode is what keeps
  production read-only. A project that wants Claude to write to its dev database switches `db-dev`
  alone to unrestricted and grants its dev role write access; the mode adds no privilege the role
  lacks. MCP permissions live in `.claude/settings.json`, never in `.mcp.json`. What `unlock db`
  means for a production server with write access is in [docs/unlock.md](../unlock.md). Where:
  `templates/common/.mcp.json`, and `templates/common/.claude/DATABASE.example.md` § Rules for the
  production server.
- **Rarely used servers load on demand.** Every configured MCP server adds its tool list to every
  session. So `.mcp.json` holds only the servers the commands and hooks expect (Serena, GitHub,
  Context7 and the two database servers). Servers you reach for now and then (a deploy platform, a
  VPS provider, Cloudflare) ship as `.claude/mcp/*.example.json` files, loaded for one session
  with `claude --mcp-config`. The deploy-platform and VPS-provider examples use neutral server
  names and env keys that stand for whatever your package reads, so the kit ties you to no
  platform. Where: `templates/common/.claude/OPERATIONS.example.md` § MCP servers, and the `mcp`
  question in `templates/common/_kit/setup.json`.
- **The pin placeholder is not version-shaped.** The on-demand examples pin their package to
  `<pinned-version>`. `ai-config.sh` skips `*.example.json` files but checks every copy, and
  `<pinned-version>` is not a version, so a copy fails the pin check until someone writes a real,
  verified one. A version-shaped placeholder such as `0.0.0-x` would pass unfilled. Where: check 4
  in `templates/common/scripts/check/ai-config.sh`.
- **Serena runs in its Claude Code context.** `.mcp.json` starts Serena with
  `--context claude-code`, which leaves out Serena's own tools for reading and creating files,
  searching file text and running shell commands (`read_file`, `create_text_file`,
  `search_for_pattern`, `execute_shell_command` in the pinned 1.7.0). Those jobs stay with Claude
  Code's own tools, where the deny rules and safety-check apply, and the hooks that watch writes
  also match Serena's editing tools. Where: `templates/common/.mcp.json`, and the matchers in
  `plugins/*/hooks/hooks.json`.

### Commands

- **Production migrations and strip pushes are yours too.** Like every push to `dev` and `prod`
  ([promote](../agent-core/promote.md)), `/agent-core:promote` and
  `/agent-deploy:promote-deploy` hand you each production migration as a `!` command: it runs as
  the database owner role, which the agent's database role never gets. Where promote-deploy has to
  strip the AI config from `prod` by hand, each push of that step is yours as well. Where:
  `plugins/agent-core/commands/promote.md` § 2.3, and
  `plugins/agent-deploy/commands/promote-deploy.md` §§ 2.3 and 2.4.
- **The production env audit prints key names only.** Both promotion commands compare the live
  production configuration with `.env.production.example`. The live values include every secret in
  clear, so they go to a temp file that is removed on exit, and only each key's name and verdict
  (`MISSING`, `EMPTY`, `PLACEHOLDER`, `DEV VALUE`, `set`, ...) reach the transcript. Where: the
  env audit in `promote.md` § 2.3 and `promote-deploy.md` § 2.4.
- **promote-deploy checks env and migrations after the `prod` push.** In that fallback flow the
  push deploys nothing: the kit's CI deploys only when a pull request into `prod` merges, the flow
  has none, and the command deploys later itself. If your platform deploys on its own whenever
  `prod` changes, the command says to run those checks before the push instead. Where:
  `promote-deploy.md` § 2.2.
- **No command writes GitHub's skip-CI marker.** Every workflow runs on pull request events only,
  so a push has no run to skip. A marker on the head commit of a later pull request would skip that
  pull request's checks and, on a promotion, the production deploy. Where: `promote.md` § 2.1,
  `promote-deploy.md` § 2.1, `templates/common/.claude/OPERATIONS.example.md` § GitHub and CI,
  and `actions/strip-ai/scripts/strip-ai.sh`.
- **Commands cite the branch model instead of restating it.** The workflow commands act on
  `internal/{scope}` → `dev` → `prod` and point to CLAUDE.md § Branching as its source (the
  be-hono, ai-fastapi, fe-nextjs and docs-nextra starters carry that section), so the model is
  written down once. They keep the `internal/` prefix wherever they act on it: merge-pr deletes an
  `internal/*` head by name after its merge, and branch-cleanup clears merged `internal/…` branches
  once you confirm the list. Both keep a long-lived scope branch you name, which OPERATIONS then
  fast-forwards after each promotion. Where: `plugins/agent-core/commands/merge-pr.md` Steps 3 and
  5, `branch-cleanup.md` Step 2, and OPERATIONS § GitHub and CI.
- **Shared commands keep repo facts in the repo.** A plugin's command is the same for every repo,
  so it names no deploy platform, migration command or health script. promote and promote-deploy
  read the deploy adapter and the migration commands from `.claude/OPERATIONS.md` § Deploys and
  stop to ask while a placeholder is unfilled. rca runs a health-check script only if the repo ships
  one, since the kit ships none. Where: "This repo's deploy target" in `promote.md`, and Step 0 of
  `plugins/agent-core/commands/rca.md`.

### Templates

- **Language rules live in language folders.** Advice that differs by language sits under
  `.claude/rules/typescript/` or `.claude/rules/python/`, and each file's `paths:` names only that
  language's files, so the text that loads always matches the file being edited. Setup's
  `language` question installs only the folders your code needs. Where:
  `templates/common/.claude/rules/`, and `templates/common/_kit/setup.json`.
- **Reference docs load on demand.** CLAUDE.md lists files such as `.claude/OPERATIONS.md` in an
  On-demand References table and never `@`-imports them, because an import loads the whole file
  into every session. `ai-config.sh` fails on an import, even one inside an HTML comment, and when
  the always-loaded text passes 15,000 bytes. Where: check 2 in `ai-config.sh`, and the header of
  `OPERATIONS.example.md`.
- **A rule citation needs a real definition.** `ai-config.sh` accepts `Rule N` only when AGENTS.md
  defines N in a heading, a bold or list lead, or a table row. A mention in prose does not count,
  so a citation left behind by a renumbering fails. Where: check 1 in `ai-config.sh`.
- **Checks fail closed too.** A check that cannot read its input fails; it never passes unread.
  `ai-config.sh` fails its hook and MCP-pin checks without python3. `double-assertion.sh` exits 2
  outside a git work tree. `pr-ready.sh` reports review threads it could not load as UNREAD, never
  as zero, and a skipped or neutral check is not a pass. `gates.sh` runs each gate with stdin
  closed, so a gate that reads stdin cannot swallow the rest of `gates.list`. Where: those scripts
  under `templates/common/scripts/`.
- **The hook probes run only when a hooks file is staged.** In pre-commit (`gates.sh --hook`), a
  staged code file runs every gate except a hooks-only line: the probes take minutes, so a commit
  reaches them only when it stages a file they prove. Without `--hook`, every line runs. Where: the
  header of `templates/common/scripts/check/gates.sh`.
- **The skills scan stays on your machine by default.** `skills.sh --static`, the default and what
  CI runs, is fully local. `--llm` sends the full text of every scanned file to a model provider
  and says so, so it is for a deliberate review only. Where: the header of
  `templates/common/scripts/check/skills.sh`.

## Consequences

- Reversing one of these choices is an ordinary change, but it updates this record in the same pull
  request, with the new reason.
- Each choice names the file that shows it today. If a choice and its file disagree, the file is
  what runs: fix this record, or the file, in the same pull request.
- Several choices trade convenience for safety (the plain-text fallback, the sticky opt-in, the `!`
  handoffs). The limits they leave are listed in [docs/unlock.md](../unlock.md).
