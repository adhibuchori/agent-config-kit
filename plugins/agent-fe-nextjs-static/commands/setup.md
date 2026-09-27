---
description: Install agent-fe-nextjs-static's permissions, static-site rules, check scripts, lint and budget configs and pull-request CI caller into this Next.js site, after a dry run you approve
argument-hint: "[--answer id=value ...]"
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Bash(git status:*), Bash(command -v agent-setup), Bash(agent-setup questions:*), Bash(agent-setup plan:*), Bash(agent-sync check:*)
---

# Set up agent-fe-nextjs-static in this repo

For a company-profile, landing or marketing site built with Next.js and prerendered at build time.
A plugin cannot carry permissions, rules or a repo's own scripts, so this command installs them as
files. Nothing is written until the user has seen the whole draft and replied **go**. Existing
files are never overwritten: the only edits to files that already exist are the managed merges the
draft lists (`.claude/settings.json`, one block each in `.gitignore` and `CLAUDE.md`, missing
`package.json` scripts).

Arguments: `$ARGUMENTS`. Each `--answer id=value` there answers that question in advance; ask only
the rest.

Every step runs in this order, and none is skipped. The engine is agent-core's `agent-setup`; the
templates path below is written out in full because the Bash tool does not export
`CLAUDE_PLUGIN_ROOT`.

## 0. Check the engine

Run `command -v agent-setup`. If it prints nothing, stop and tell the user: `agent-setup` ships in
agent-core, which this plugin depends on; install or enable it
(`/plugin install agent-core@agent-config-kit`), then run `/agent-fe-nextjs-static:setup` again.
It needs python3 3.8 or newer.

## 1. Explore (read-only)

Read what setup would touch, and note what you find, with the file as evidence:

- `next.config.*`: does it set `output: 'export'`? That is **export** mode; otherwise the site is in
  **ssg-with-endpoints** mode. Also note `headers()`, `redirects()` or `rewrites()` in it: under
  export they are ignored, so they must move to the host's config after setup.
- The app tree (`app/` or `src/app/`): route handlers (`**/route.ts`), `'use server'` files,
  `proxy.ts` / `middleware.ts`, dynamic segments (`[slug]`), `not-found.tsx`, `robots.ts`,
  `sitemap.ts`, `opengraph-image.*`. Say which mode they point to and what would fail the
  static-export check.
- `package.json` and the lockfile: the package manager, and whether `next-intl`, `@lhci/cli`,
  `pa11y-ci`, `@axe-core/cli`, `oxlint`, `oxfmt`, `knip` and `typescript` are present. Scripts the
  kit also names (`lint`, `format`, `fl:ci`, `type-check`, `check:*`, `serve:build`) that exist
  with another value are kept and show as `conflict` lines. With no `package.json`, setup adds no
  scripts and no `unlock` alias; a later `/agent-fe-nextjs-static:sync` adds them.
- The host: `public/_headers`, an nginx config, or another file that sets response headers; what
  sets the production origin (`NEXT_PUBLIC_SITE_URL` or a hard-coded `metadataBase`).
- `.claude/settings.json` and `.claude/settings.local.json`: a `hooks` key running any
  `.claude/hooks/*.sh` from a copied template. With the plugins enabled, each of those runs twice
  (double wiring); setup never edits `hooks`, so the user removes those entries.
- `CLAUDE.md`, `AGENTS.md` and `SSOT.md`. Where one is missing, setup creates it from this plugin's
  starter. Where `AGENTS.md` exists it is kept; offer to show
  `${CLAUDE_PLUGIN_ROOT}/templates/fe-nextjs-static/AGENTS.md.starter` so the user can merge the
  static-site rules they want by hand.
- `.claude/agent-config-kit.lock`: if it already lists `agent-fe-nextjs-static`, stop and point the
  user at `/agent-fe-nextjs-static:sync`. If it lists `agent-fe-nextjs`, `agent-docs-nextra`,
  `agent-be-hono` or `agent-ai-fastapi`, stop: one primary stack plugin per repo, and `plan`
  refuses the combination. A site that has signed-in areas or client data fetching is an app:
  suggest agent-fe-nextjs instead.
- `git status --short`. If the tree is dirty, say so, and suggest committing first so the setup
  lands as a change of its own.

## 2. Ask, one question at a time

Run:

```bash
agent-setup questions --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack fe-nextjs-static --json
```

The list starts with agent-core's questions when this repo has no agent-core setup yet; that layer
is planned in the same draft. For each question the arguments did not answer:

- ask it on its own, with its choices;
- give the **recommended** answer and one line of why, adjusted by what step 1 found: cite the file
  (for example, `package.json` depends on `next-intl`, so `i18n` is probably yes; an nginx config
  sets the headers, so `headers` is probably no);
- accept "ok" as the recommended answer, and wait for the reply before the next question.

## 3. Draft

Run `agent-setup plan` with every answer:

```bash
agent-setup plan --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack fe-nextjs-static --answer <id>=<value> ...
```

Show its output verbatim: every create, same, keep, seed, merge, conflict, block, alias, warn and
lock line, and the digest. Below it, add at most three lines on what matters here (a `keep` of a
file the user may want to compare, a `conflict`, a `warn` about double wiring). End with:
"Reply **go** to write exactly this."

## 4. Write only on "go"

On **go**, run `agent-setup apply` with the same answers and the digest from step 3:

```bash
agent-setup apply --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack fe-nextjs-static --answer <id>=<value> ... --digest sha256:<hex>
```

`apply` is left out of this command's allowed tools on purpose, so the user's permission prompt is a
second, independent confirmation. Any reply other than **go** writes nothing. If `apply` exits 3,
the repo changed since the draft: go back to step 3 and show the new plan.

## 5. Verify and hand over

Run:

```bash
agent-sync check --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack fe-nextjs-static
```

Report its exit code and findings (0 means in sync). Then tell the user, briefly:

- Commit the new files together with `.claude/agent-config-kit.lock`: the lock is what turns the
  hooks on for everyone who clones the repo.
- Set the production origin: `siteUrl` in `scripts/check/site.config.json`, or
  `NEXT_PUBLIC_SITE_URL` (see `.env.example`). The build checks fail until one is set. If
  `next.config` computes `output`, pin `mode` there too.
- The gates call tools the repo must have; setup installs none of them. The source gates need
  `oxfmt oxlint knip typescript` as dev dependencies (and `husky`, with `"prepare": "husky"` in
  `package.json`, so `.husky/pre-commit` runs `gates.sh`). The browser checks need `pa11y-ci` (or
  `@axe-core/cli`) and, when `lighthouserc.json` was installed, `@lhci/cli` with Chrome. The checks
  in `scripts/check/` themselves need only Node.js 20 or newer.
- Move anything step 1 found that a static export ignores: `headers()` into `public/_headers` (or
  the host's file), redirects into the host's redirect config, a `POST` route handler to a separate
  endpoint (`.claude/rules/web/forms-on-static-hosting.md`).
- Placeholders left to fill: `<Site Name>` and the snapshot in `CLAUDE.md`, the sections of
  `SSOT.md`, and `localePairs` in `.claude/agent-config.json` when the i18n module was installed.
- Next: build the site and run `node scripts/check/site-audit.mjs`, or
  `/agent-fe-nextjs-static:launch-checklist` before the site goes live.
