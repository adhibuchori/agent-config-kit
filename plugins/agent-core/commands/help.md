---
description: Shows which agent-config-kit command to run next (plan → review → commit → create-pr → merge-pr), lists every command of every kit plugin, and explains how the user unlocks .env files and database writes. Reads only.
argument-hint: "[what you want to do]"
---

# /agent-core:help — Which Command Next

**Question:** $ARGUMENTS

Answer the question with the one command that fits, from the tables below, and why, for the user to
type: the commands that install files, commit, push, merge or post to GitHub (every setup and
sync, commit, create-pr, merge-pr, resolve-pr-review, ship, promote, branch-cleanup, checkpoint,
and agent-deploy's two) are user-only, so never try to start one yourself. With no
question, print the flow and the table of installed plugins' commands. Mark a command whose plugin
is not enabled in this session as "not installed" (the available commands are listed in your
context), and say which plugin adds it.

## The everyday flow

```text
 /agent-core:plan ──> write code ──> /agent-core:review ──> /agent-core:commit
                                           │                       │
                                   fix what it found          /agent-core:create-pr ──> /agent-core:merge-pr
                                                                                              │
                          /agent-core:ship = review + security review + fix + commit + push   │
                          /agent-core:promote = PR to dev, dev → prod, verify the deploy <────┘
```

| Step | Command | What it does |
| --- | --- | --- |
| 1 | `/agent-core:plan` | Scope, tasks, data, risks and open questions before any code; waits for your yes |
| 2 | `/agent-core:review` | Reviews staged work (or the branch) through the stack's reviewer; reports by severity, changes nothing |
| 3 | `/agent-core:commit` | Runs the gates and drafts the commit message; you commit |
| 4 | `/agent-core:create-pr` | Drafts the PR from the repo's template, confirms it, pushes and opens it into `dev` |
| 5 | `/agent-core:merge-pr` | Checks readiness, confirms, merges with a merge commit, deletes an `internal/*` head by name |

## Every command

### agent-core (every repo)

| Command | Use it when |
| --- | --- |
| `/agent-core:help` | You are not sure which command fits |
| `/agent-core:setup` | First time in a repo: installs permissions, rules, check scripts and the unlock and `.env` helpers after a dry run you approve |
| `/agent-core:sync` | After updating the plugin, or to check the repo (`--check`: drift and double hook wiring, non-zero exit) |
| `/agent-core:plan` | Before building anything non-trivial |
| `/agent-core:review` | Before committing, or to review a branch |
| `/agent-core:commit` | Staged work is ready and you want the gates run and a message drafted |
| `/agent-core:create-pr` | The branch is pushed-ready and needs a PR into `dev` |
| `/agent-core:merge-pr` | A PR is approved and green |
| `/agent-core:resolve-pr-review` | A PR has review comments to triage, apply and answer |
| `/agent-core:ship` | Finished work should go from "written" to "pushed" in one pass, every finding fixed |
| `/agent-core:promote` | A branch should reach production: PR to `dev`, promotion PR to `prod`, deploy verified |
| `/agent-core:branch-cleanup` | After a promotion, to delete merged branches (after you confirm the list) |
| `/agent-core:rca` | A bug needs its root cause: reproduce first, fix with a test that fails without it (`/debug` means this) |
| `/agent-core:check-fix` | A gate is red: run the gates, fix each failure at its cause, re-run until green |
| `/agent-core:checkpoint` | Before a risky change: a local safety commit of this session's files |
| `/agent-core:checkpoint-summary` | Handing the session over: what was done, what is pending |
| `/agent-core:learn-session` | The session taught something that should change next time |

### Stack plugins (install one per repo; each includes agent-core)

| Command | Plugin | Use it when |
| --- | --- | --- |
| `/agent-fe-nextjs:setup` · `/agent-fe-nextjs:sync` | agent-fe-nextjs | Setting up or checking a Next.js web app |
| `/agent-fe-nextjs:a11y-audit` | agent-fe-nextjs | Auditing a page's accessibility |
| `/agent-fe-nextjs:review-soc` | agent-fe-nextjs | Checking separation of concerns in components |
| `/agent-fe-nextjs:plan-fullstack` | agent-fe-nextjs | Planning a change that spans the frontend and its API |
| `/agent-fe-nextjs-static:setup` · `/agent-fe-nextjs-static:sync` | agent-fe-nextjs-static | Setting up or checking a company-profile or landing site |
| `/agent-fe-nextjs-static:review` | agent-fe-nextjs-static | Reviewing a static site (accessibility, performance, Core Web Vitals) |
| `/agent-fe-nextjs-static:a11y-audit` | agent-fe-nextjs-static | Auditing built pages with an accessibility checker |
| `/agent-fe-nextjs-static:seo-audit` | agent-fe-nextjs-static | Checking robots, sitemap, canonical, hreflang, metadata and OG images |
| `/agent-fe-nextjs-static:launch-checklist` | agent-fe-nextjs-static | Before a site goes live |
| `/agent-be-hono:setup` · `/agent-be-hono:sync` | agent-be-hono | Setting up or checking a Bun + Hono + Drizzle API |
| `/agent-ai-fastapi:setup` · `/agent-ai-fastapi:sync` | agent-ai-fastapi | Setting up or checking a FastAPI service |
| `/agent-docs-nextra:setup` · `/agent-docs-nextra:sync` | agent-docs-nextra | Setting up or checking a Nextra docs site |

### Optional add-ons

| Command | Plugin | Use it when |
| --- | --- | --- |
| `/agent-fe-threejs:setup` · `/agent-fe-threejs:sync` | agent-fe-threejs | Adding 3D scene rules to a web app |
| `/agent-deploy:setup` · `/agent-deploy:sync` | agent-deploy | Setting up the deploy commands |
| `/agent-deploy:promote-deploy` | agent-deploy | Promoting and deploying in one flow |
| `/agent-deploy:verify-deploy` | agent-deploy | Checking that a deploy really reached production |

## Unlocking `.env` files and database writes

Two things are locked by default, and only the user opens them: changing `.env*` files (`env`, 20
minutes) and SQL that writes to the production database (`db`, 15 minutes). The user types the
command with `!` in front, so it runs as them, outside Claude's hooks:

| The repo uses | Open `.env*` | Open DB writes | Lock everything |
| --- | --- | --- | --- |
| bun | `! bun unlock env` | `! bun unlock db` | `! bun unlock off` |
| npm | `! npm run unlock env` | `! npm run unlock db` | `! npm run unlock off` |
| pnpm | `! pnpm unlock env` | `! pnpm unlock db` | `! pnpm unlock off` |
| yarn | `! yarn unlock env` | `! yarn unlock db` | `! yarn unlock off` |
| no Node | `! ./scripts/ops/unlock.sh env` | `! ./scripts/ops/unlock.sh db` | `! ./scripts/ops/unlock.sh off` |

- `status` shows what is open and until when; a number of minutes (1 to 240) sets the length.
- Claude never unlocks: the hooks refuse it running the script, its package alias, or writing the
  unlock files. Asking in the chat unlocks nothing.
- Locked or not, Claude lists a `.env` file with `bash scripts/env/show.sh <file>` (secrets
  masked) and reads the database with one read-only statement.
- The package-manager forms need the `unlock` script in `package.json`, which `/agent-core:setup`
  adds when the repo has one. The full story is `docs/unlock.md` in the repo.
