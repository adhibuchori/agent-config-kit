---
description: Install agent-fe-nextjs's permissions, TypeScript and web rules, anti-patterns, gate scripts, lint configs and pull-request CI caller into this Next.js app, after a dry run you approve
argument-hint: "[--answer id=value ...]"
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Bash(git status:*), Bash(command -v agent-setup), Bash(agent-setup questions:*), Bash(agent-setup plan:*), Bash(agent-sync check:*)
---

# Set up agent-fe-nextjs in this repo

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
(`/plugin install agent-core@agent-config-kit`), then run `/agent-fe-nextjs:setup` again. It needs
python3 3.8 or newer.

## 1. Explore (read-only)

Read what setup would touch, and note what you find, with the file as evidence:

- `package.json` and the lockfile. The check scripts run on Bun, and the gate list, the package
  scripts and the permissions call `bun`; with `package-lock.json`, `pnpm-lock.yaml` or `yarn.lock`
  the repo still needs Bun installed to run the checks, so say so. With no `package.json`, setup adds
  no scripts and no `unlock` alias; a later `/agent-fe-nextjs:sync` adds them once it exists.
- `package.json` scripts the kit also names (`lint`, `format`, `test`, `type-check`, `check:*`): a
  script that exists with another value is kept and shows as a `conflict` line, and the gate that
  calls it then runs the user's version.
- `.claude/settings.json` and `.claude/settings.local.json`: a `hooks` key that runs
  `generated-guard.sh`, or any `.claude/hooks/*.sh` from a copied template. With the plugins enabled,
  each of those runs twice (double wiring); setup never edits `hooks`, so the user removes those
  entries.
- `CLAUDE.md`, `AGENTS.md` and `SSOT.md`. Where one is missing, setup creates it from this plugin's
  starter. Where `AGENTS.md` exists it is kept, and the installed rules and reviewer cite rule numbers
  from the starter (Rules 5-34): `scripts/check/ai-config.sh` fails on a cited number `AGENTS.md`
  does not define. Offer to show `${CLAUDE_PLUGIN_ROOT}/templates/fe-nextjs/AGENTS.md.starter` so the
  user can merge the rules they want by hand.
- `.gitignore`, and `.claude/agent-config.json` (does it already set `generatedPaths` or
  `localePairs`?).
- The stack's markers: `next.config.*`, `src/app/`, `src/components/`, `orval.config.*` and
  `openapi.json` (the generated client the guard protects), and the evidence each question's `detect`
  names: `next-intl` in `package.json`, `src/messages/*.json`, `@radix-ui/react-dialog` or a
  `dialog.tsx`, `src/styles/globals.css`, `*-skeleton.tsx` files, `.github/workflows/`.
- `.claude/agent-config-kit.lock`: if it already lists `agent-fe-nextjs`, stop and point the user at
  `/agent-fe-nextjs:sync`. If it lists `agent-fe-nextjs-static`, `agent-docs-nextra`,
  `agent-be-hono` or `agent-ai-fastapi`, stop: one primary stack plugin per repo, and `plan` refuses
  the combination.
- `git status --short`. If the tree is dirty, say so, and suggest committing first so the setup lands
  as a change of its own.

## 2. Ask, one question at a time

Run:

```bash
agent-setup questions --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack fe-nextjs --json
```

The list starts with agent-core's questions when this repo has no agent-core setup yet; that layer is
planned in the same draft. For each question the arguments did not answer:

- ask it on its own, with its choices;
- give the **recommended** answer and one line of why, adjusted by what step 1 found: cite the file
  (for example, `package.json` depends on `next-intl`, so `i18n` is probably yes);
- accept "ok" as the recommended answer, and wait for the reply before the next question.

## 3. Draft

Run `agent-setup plan` with every answer:

```bash
agent-setup plan --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack fe-nextjs --answer <id>=<value> ...
```

Show its output verbatim: every create, same, keep, seed, merge, conflict, block, alias, by-hand, warn
and lock line, and the digest. Below it, add at most three lines on what matters here (a `keep` of a
file the user may want to compare, a `conflict`, a `warn` about double wiring). End with:
"Reply **go** to write exactly this."

## 4. Write only on "go"

On **go**, run `agent-setup apply` with the same answers and the digest from step 3:

```bash
agent-setup apply --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack fe-nextjs --answer <id>=<value> ... --digest sha256:<hex>
```

`apply` is left out of this command's allowed tools on purpose, so the user's permission prompt is a
second, independent confirmation. Any reply other than **go** writes nothing. If `apply` exits 3, the
repo changed since the draft: go back to step 3 and show the new plan.

## 5. Verify and hand over

Run:

```bash
agent-sync check --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack fe-nextjs
```

Report its exit code and findings (0 means in sync). Then tell the user, briefly:

- Commit the new files together with `.claude/agent-config-kit.lock`: the lock is what turns the hooks
  on for everyone who clones the repo.
- The gates call tools the repo must have. Setup installs none of them; the user runs
  `bun add -d husky knip oxfmt oxlint vitest @vitest/coverage-v8 jsdom typescript` (plus
  `playwright-core` to keep `measure:waterfall`) and adds `"prepare": "husky"` to `package.json`, so
  `.husky/pre-commit` runs `gates.sh` on every commit. Without Bun, no check under `scripts/` runs.
- The `by-hand` lines: the coverage block for `vitest.config.ts` and the `tsconfig.json` exclusion,
  shown in the draft. `coverage-policy.mjs` fails until the coverage block is in place.
- Placeholders left to fill: `<Project Name>` and the snapshot in `CLAUDE.md`, the sections of
  `SSOT.md` and the `<backend-service>` names in `AGENTS.md` when setup created them, and the handle
  in `.github/CODEOWNERS`.
- The guard protects `src/lib/api/generated`, `src/generated` and `openapi.json` / `.yaml` / `.yml`
  by default. If generated output lives elsewhere, set `generatedPaths` in
  `.claude/agent-config.json`; a list there replaces the default whole, so repeat the defaults you
  still want.
- `.github/workflows/quality-gate.yaml` runs on pull requests into `dev`, `prod`, `main` and
  `master`, and calls the kit's reusable workflow pinned to one commit.
