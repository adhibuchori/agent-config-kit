---
description: Install agent-docs-nextra's rules, anti-patterns, gate scripts, lint config and pull-request CI into this Nextra docs repo, after a dry run you approve
argument-hint: "[--answer id=value ...]"
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Bash(git status:*), Bash(command -v agent-setup), Bash(agent-setup questions:*), Bash(agent-setup plan:*), Bash(agent-sync check:*)
---

# Set up agent-docs-nextra in this repo

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
(`/plugin install agent-core@agent-config-kit`), then run `/agent-docs-nextra:setup` again. It needs
python3 3.8 or newer.

## 1. Explore (read-only)

Read what setup would touch, and note what you find, with the file as evidence:

- `package.json` and the lockfile. `bun.lock` or `bun.lockb` is what the gate list, the CI caller and
  the permissions assume; another lockfile (`package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`) means
  the user will edit `scripts/check/gates.list` after setup, so say so. With no `package.json`,
  setup adds no scripts and no `unlock` alias.
- `.claude/settings.json` and `.claude/settings.local.json`: a `hooks` key that runs
  `generated-guard.sh`, or any `.claude/hooks/*.sh` from a copied template. With the plugins enabled,
  each of those runs twice (double wiring); setup never edits `hooks`, so the user removes those
  entries.
- `CLAUDE.md`, `.gitignore`, and `.claude/agent-config.json` (does it already set `generatedPaths`?).
- The stack's markers: `next.config.*` wrapping `nextra`, `content/` with `_meta.js` files,
  `scripts/generate/`, `wrangler.jsonc`, `app/` or `components/` `.tsx` files, and
  `.github/workflows/`.
- `.claude/agent-config-kit.lock`: if it already lists `agent-docs-nextra`, stop and point the user
  at `/agent-docs-nextra:sync`.
- `git status --short`. If the tree is dirty, say so, and suggest committing first so the setup lands
  as a change of its own.

## 2. Ask, one question at a time

Run:

```bash
agent-setup questions --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack docs-nextra --json
```

The list starts with agent-core's questions when this repo has no agent-core setup yet; that layer is
planned in the same draft. For each question the arguments did not answer:

- ask it on its own, with its choices;
- give the **recommended** answer and one line of why, adjusted by what step 1 found: cite the file
  (for example, `scripts/generate/changelog/` exists, so `generated-pages` is probably yes);
- accept "ok" as the recommended answer, and wait for the reply before the next question.

## 3. Draft

Run `agent-setup plan` with every answer:

```bash
agent-setup plan --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack docs-nextra --answer <id>=<value> ...
```

Show its output verbatim: every create, same, keep, seed, merge, conflict, block, alias, warn and lock
line, and the digest. Below it, add at most three lines on what matters here (a `keep` of a file the
user may want to compare, a `conflict`, a `warn` about double wiring). End with:
"Reply **go** to write exactly this."

## 4. Write only on "go"

On **go**, run `agent-setup apply` with the same answers and the digest from step 3:

```bash
agent-setup apply --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack docs-nextra --answer <id>=<value> ... --digest sha256:<hex>
```

`apply` is left out of this command's allowed tools on purpose, so the user's permission prompt is a
second, independent confirmation. Any reply other than **go** writes nothing. If `apply` exits 3, the
repo changed since the draft: go back to step 3 and show the new plan.

## 5. Verify and hand over

Run:

```bash
agent-sync check --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack docs-nextra
```

Report its exit code and findings (0 means in sync). Then tell the user, briefly:

- Commit the new files together with `.claude/agent-config-kit.lock`: the lock is what turns the hooks
  on for everyone who clones the repo.
- The gates call tools the repo must have: `bun add -d husky knip oxfmt oxlint typescript @types/bun`,
  and `"prepare": "husky"` in `package.json` so `.husky/pre-commit` runs `gates.sh`. Setup installs
  none of them. `tsconfig.json` needs `"types": ["bun"]` for the scripts under `scripts/`.
- `scripts/next/env.ts` (the environment preflight) and `scripts/next/run.mjs` (the Next.js launcher
  that works around Node 25's web storage) run only once `dev` and `build` call them. Setup never
  changes a script the repo already has, so offer these two `package.json` scripts to paste:

  ```text
  "dev": "bun run scripts/next/env.ts check development --soft && node scripts/next/run.mjs dev",
  "build": "bun run scripts/next/env.ts check production --soft && node scripts/next/run.mjs build && pagefind --site .next/server/app --output-path out/_pagefind"
  ```

  The last step of `build` indexes the site for Nextra's search and needs `pagefind` as a dev
  dependency; a site that searches another way drops it. `bun run env:init` (a script setup adds)
  creates a missing `.env.<target>` from its `.example`, and leaves an existing one alone.
- Where the CI pipeline was installed: `bun add -d -E wrangler@3.114.17`, the release
  `ci-cd.yaml` deploys with, and the repository secrets `APP_REPO_TOKEN`, `CLOUDFLARE_API_TOKEN`
  and `CLOUDFLARE_ACCOUNT_ID`.
- Placeholders left to fill: the table in `.claude/rules/docs-site/content.md`, the project name in
  `CLAUDE.md` when setup created it, and, where installed, `APP_REPO` in
  `.github/workflows/changelog.yaml` and the three values in `wrangler.example.jsonc` (copied to
  `wrangler.jsonc`).
- If the generators write somewhere other than `content/technical` and `content/changelog.mdx`, list
  those paths under `generatedPaths` in `.claude/agent-config.json`; until then the guard protects
  nothing on this site.
- `.github/workflows/quality-gate.yaml` runs on pull requests into `dev` and `prod`, so it starts once
  those branches exist.
