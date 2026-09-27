---
description: Fallback promotion for when CI cannot run. Proves CI is down, runs the gates locally, merges internal/<scope> into dev and dev into prod without a pull request (the user pushes), strips the AI config from prod by hand where the repo strips it, audits the production env and migrations, deploys through the repo's deploy adapter, verifies the deployment by time, and commits a run log of what CI still owes
argument-hint: "[internal/<scope>]"
disable-model-invocation: true
---

# /agent-deploy:promote-deploy — Promote Without Relying On CI

Same destination as `/agent-core:promote`, through the same hops (the branch model in CLAUDE.md
§ Branching: `internal/{scope}` → `dev` → `prod`), different assumption: **CI cannot be trusted to
run.** Use this only when GitHub Actions is blocked (a spending limit) or every runner pool is gone,
so the usual green-checks-then-merge flow would block forever. If only one pool is gone, flip its
variable instead (`.claude/CI-RUNNERS.md` § Escape hatches) and use `/agent-core:promote`.

**Prefer `/agent-core:promote`.** This command trades away every automated gate. Reach for it when
the alternative is production going stale, not to save a few minutes. Only the user starts it.

**Pushes to `dev` and `prod` are the user's.** agent-core's safety hook and deny rules refuse them
from Claude, however they are asked. Where this command needs one, ask the user to type
`! git push …` in the prompt, and wait for its output before going on.

**Arguments:** $ARGUMENTS (the `internal/{scope}` branch to promote; ask when it is not given)

---

## This repo's deploy target

Phases 2 and 3 need this repo's deploy target (platform, app, live URL), the four adapter operations
below and its migration facts. This command is shared by every repo that installs agent-deploy, so
those values live in the repo: `.claude/OPERATIONS.md` § Deploys (start it from
`.claude/OPERATIONS.example.md`, which agent-core installs). Read that section first. If it has no
target, or a `<command>` placeholder is still unfilled, stop and ask the user for the missing values,
and offer to record them there before going on.

**Deploy adapter.** The operations this command needs, as this repo runs them. The
`deploy-platform` MCP server (`.claude/mcp/deploy-platform.example.json`, loaded on demand) usually
covers `latest`, `trigger` and `backup`; the platform's API or CLI covers `read-env` when the MCP
server redacts env values, which it should. Nothing here may depend on a GitHub Actions runner.

- `read-env <file>`: writes the live production configuration (runtime env and build arguments) to
  `<file>`, one `KEY=VALUE` per line, or one bare `KEY` per line where the platform shows names
  only. Prints nothing.
- `latest`: prints the newest deployment's id, status and created-at timestamp (ISO 8601).
- `trigger`: starts a deploy of `prod`, and exits non-zero when the platform declines it. For a
  deploy webhook this is `bash scripts/deploy/trigger-deploy.sh refs/heads/prod`, which
  `/agent-deploy:setup` installs; the user runs it (Phase 3).
- `backup`: takes a manual database backup and prints where it landed.

**Quality gate for this repo:**

```bash
bash scripts/check/gates.sh                   # every gate in scripts/check/gates.list
<the production build CLAUDE.md names>        # when the gates do not already run it
```

A repo without `scripts/check/gates.list` runs the gates CLAUDE.md § Quality Gates lists instead.

---

## What this skips, and what replaces it

| `/agent-core:promote` relies on    | Here instead                                           |
| ---------------------------------- | ------------------------------------------------------ |
| CI running the quality gate        | `bash scripts/check/gates.sh`, Phase 1                 |
| PR review and bot review           | Nothing. State this plainly in the report.             |
| A strip workflow cleaning `prod`   | The same steps, run by hand, Phase 2.3 (if it strips)  |
| A deploy triggered by CI           | The adapter's `trigger`, Phase 3                       |
| Green checks as merge evidence     | Local gate output as merge evidence                    |

The kit's workflows run only on pull request events, and this command opens no pull request, so its
pushes create no workflow run at all. It therefore costs **zero runner minutes**, which also means
nothing runs to catch a mistake. Everything in the right-hand column above is yours to actually do.

---

## Phase 0 — Confirm CI is genuinely unavailable

Do not skip this. If CI works, stop and use `/agent-core:promote`.

```bash
gh run list --limit 5 --json name,status,conclusion,createdAt
```

Read it unfiltered. Two signatures worth telling apart:

- **Spending limit**: the job dies in about three seconds with no steps. The reason is in the
  check-run annotation, not the run log: `gh api repos/{owner}/{repo}/check-runs/<id>` (with RTK
  installed, `rtk proxy gh api …`, which keeps the annotation text whole), and look for the billing
  or spending-limit message.
- **Runner minutes exhausted, or no runner available**: the job is created but never starts;
  `started_at` stays far behind `created_at` and `runner_name` is empty.

A job queued for hours is not the same as a job that cannot run. Queue time costs nothing: wait it
out rather than bypassing the gates.

### 0.1 Open the run log

Every use of this command leaves a record. Create it **now**, before any change, so an abandoned
promotion is still visible:

```bash
mkdir -p promote-deploy-logs
LOG="promote-deploy-logs/$(date -u +%Y-%m-%dT%H%M)-$(git branch --show-current | tr / -).md"
```

Two lists, settled at different times. The first you tick as you go. The second is **debt owed to
CI**, things only a runner can do, and it stays open until the runner is back.

```markdown
# promote-deploy — <scope>

- **Started (UTC):** <timestamp>
- **Reason CI unavailable:** <spending limit | no runner> + the evidence from Phase 0
- **Promoted commit:** `<prod sha>`
- **Settled:** <blank until every box below is ticked>

## Done by hand during the promotion

- [ ] Phase 1 — gates.sh passed (paste the last lines)
- [ ] 2.1 — merged to dev — `<sha>`
- [ ] 2.2 — merged to prod — `<sha>`
- [ ] 2.3 — AI config stripped from prod and verified, or: this repo does not strip
- [ ] 2.4 — production env matches the template; migrations run and verified
- [ ] 3.1 — deployed
- [ ] 3.2 — deployment verified — id `<id>`, created after 2.2
- [ ] 3.3 — smoke test

## Owed to CI — settle when the runner is back

Each of these ran for every other commit on prod, and not for this one.

- [ ] Re-run the quality gate on a clean runner, against `prod`
- [ ] <one box per other workflow in .github/workflows/ that runs on a pull request: review bots,
      audits, generated content>

## Skipped, and why

<PR review and bot review were skipped by definition — say what else was, and why.>
```

The record lives on `dev`. If this repo strips dev-only files from `prod`, `promote-deploy-logs/`
belongs on that list.

### Settling the debt later

When runners are available again, find every promotion still carrying open items:

```bash
grep -rl '^- \[ \]' promote-deploy-logs/
```

With RTK installed, run it as `rtk proxy grep …`: its rewrite regroups and can truncate the list.

Work each file down to zero unticked boxes, then fill in **Settled**. A log with open boxes is a
commit in production that nothing has ever checked, which is the whole reason the file exists.

---

## Phase 1 — Run the gates locally

```bash
bash scripts/check/gates.sh
```

That script runs every gate in `scripts/check/gates.list`, the list the pull-request gate runs, and
exits non-zero on the first real failure, so it enforces rather than suggests. Treat any difference
between it and the workflow as a bug in the list, not as licence to skip a check. It cannot
reproduce the runner exactly: tools installed for your platform are different builds of the same
pinned versions, so say which checks ran on which binaries. Then run the production build when the
gates do not.

If anything fails, fix it and re-run. A promotion that skips the gate _and_ skips review has nothing
left checking it at all.

---

## Phase 2 — Merge without a pull request

### 2.1 `internal/{scope}` → `dev`

```bash
git fetch origin
git checkout dev && git pull --ff-only origin dev
git merge --no-ff internal/{scope} -m "feat: <what landed>"
```

Then ask the user to type `! git push origin dev`, and wait for its output.

`--no-ff` keeps the branch's history visible. Without a pull request there is no title, so this
message is the only record of what shipped: write it as carefully as you would a pull request title.

No merge message here carries GitHub's skip-CI marker, and none needs one: a push starts no
workflow, so no CI deploy races the deploy Phase 3 performs. Never write the marker, not even in
prose. `dev` heads the next promotion pull request, and a marker on that head commit stops the pull
request's checks and, once it merges, the production deploy.

If the merge conflicts, resolve it here and re-run Phase 1 before the push. A conflict resolution is
new code that nothing has checked.

### 2.2 `dev` → `prod`

```bash
git checkout prod && git pull --ff-only origin prod
git rev-parse HEAD      # the prod commit before this promotion; 2.4 diffs against it
git merge --no-ff dev -m "chore: promote dev to prod"
```

Then ask the user to type `! git push origin prod`, and wait for its output. Record the push time
(`date -u +%Y-%m-%dT%H:%M:%SZ`): Phase 3 compares against it.

This order assumes the push itself deploys nothing: the kit's CI deploys only when a pull request
into `prod` is merged, and this push has none. If the platform deploys on its own whenever `prod`
changes (a git integration, not a CI step), run 2.4 before this push instead, diffing
`origin/prod...dev`, so the env and the schema are ready before the new code lands.

Never delete `dev` afterwards. It is the shared branch, not a disposable one.

### 2.3 Strip the AI config, where this repo strips it

Some repos remove the AI configuration (`.claude/`, `.mcp.json`, `CLAUDE.md`, `AGENTS.md` and the
like) from `prod` on every merged pull request, then merge `prod` back into `dev` so `dev` keeps it.
That runs as a workflow on a merged pull request, and this flow has none, so it never fires. Look in
`.github/workflows/` for the job that does it.

- **None:** skip to 2.4, and say in the report that this repo does not strip.
- **One:** do by hand exactly what it does, in its order, with the scripts or steps it runs. Each
  step that pushes (the strip commit to `prod`, the back-merge into `dev`) is the user's: ask them to
  type it with `!`, and read each output before the next. Skipping this leaves `prod` holding
  `.claude/`, `.claude/DATABASE.md` and its topology included: a leak, not untidiness.

Then prove it, read-only, against the path list that job strips (these four are the minimum):

```bash
git fetch origin
git ls-tree -r --name-only origin/prod -- .claude .mcp.json CLAUDE.md AGENTS.md   # must print nothing
git ls-tree -r --name-only origin/dev -- .claude | head -3                         # must still print files
```

The strip's failure mode is **silence**: a cancelled run, or half the operation landing. A strip
nobody verified did not happen.

### 2.4 Production env and schema are ready

CI checks neither, and both are how a green promotion breaks production: a database whose
migrations were never applied, a frontend whose API origin was never set and quietly fell back to a
local address. Each surfaces only when a real request hits it.

**Env against the template.** Compare the live configuration's keys, build arguments included, to
`.env.production.example` and to every variable the code's env schema reads. A code-side fallback
turns a missing key into a quiet wrong address rather than a crash, so a key that is absent, empty,
still a placeholder, or holding a development value counts as missing. The live values include
every secret in clear, so they go to a file that is removed on exit, and only key names with a
verdict reach the transcript. A repo without `.env.production.example` cannot be audited this way:
write it first (every key, placeholder values only), or report the audit as not run.

```bash
live="$(mktemp)"
trap 'rm -f "$live"' EXIT
<read-env command> "$live"   # the adapter's read-env: writes the file, prints nothing
python3 - "$live" .env.production.example <<'PY'
import re, sys

# Add this project's development-only hosts and ports to DEV.
DEV = re.compile(r"localhost|127\.0\.0\.1|0\.0\.0\.0|-dev[.:/]")
LINE = re.compile(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)(?:=(.*))?$")

def parse(path):
    found = {}
    for raw in open(path, encoding="utf-8", errors="replace"):
        match = LINE.match(raw.rstrip("\n"))
        if match and not raw.lstrip().startswith("#"):
            value = match.group(2)
            found[match.group(1)] = None if value is None else value.strip().strip("'\"")
    return found

live, template = parse(sys.argv[1]), parse(sys.argv[2])
for key in sorted(set(template) | set(live)):
    if key not in live:
        verdict = "MISSING"
    elif key not in template:
        verdict = "NOT IN TEMPLATE"
    elif live[key] is None:
        verdict = "PRESENT (value not readable)"
    elif live[key] == "":
        verdict = "EMPTY"
    elif "PLACEHOLDER" in live[key] or live[key].startswith("<"):
        verdict = "PLACEHOLDER"
    elif DEV.search(live[key]):
        verdict = "DEV VALUE"
    else:
        verdict = "set"
    print(f"{key}\t{verdict}")
PY
```

Every verdict other than `set` is a finding to resolve before Phase 3. A key added to the template
in this promotion is added to the platform before the deploy, as a read-modify-write
(`.claude/OPERATIONS.md` § Deploys): read the whole configuration, write it back with the new key,
and compare the variable count before and after.

**Migrations before the deploy lands.** A deploy that does not migrate on boot reaches the new
schema only when someone runs the migration, and the migration lands before the new code does, so
it must stay backward-compatible with the code still running.

1. List what this promotion adds: `git fetch origin`, then
   `git diff --name-only <prod commit from 2.2>..origin/prod -- <migrations-dir>` (with RTK
   installed, `rtk proxy git diff …`: its rewrite prints a line even when nothing changed).
   Nothing listed: skip to Phase 3.
2. Take a manual backup with the adapter's `backup`, and confirm the file exists where it says.
3. Hand the migration to the user. It runs as the database owner role, from their shell, with the
   production connection string they hold; Claude's database role has no DDL rights and must not
   get them. Ask them to type `! <migrate-command>` and wait for its output.
4. Verify through `db-prod`, read-only: `<applied-migrations-query>` must match the migrations on
   `prod`.

The three migration placeholders, `<migrations-dir>`, `<migrate-command>` and
`<applied-migrations-query>`, come from `.claude/OPERATIONS.md` § Deploys as well. A repo that owns
no schema depends on its backend's: before this deploy lands, confirm the backend's production
migrations match its own `prod` branch, and promote the backend first if they do not.

---

## Phase 3 — Deploy, because nothing else will

### 3.1 Deploy through the adapter

Run the adapter's `trigger`. It performs the same action the CI deploy would have, without a runner.

A static site deployed by upload (the files, not a container): build first when the deploy command
does not build, because an upload of a stale output folder publishes silently; after the upload,
load a page this change touched and confirm its content changed, because an upload of an unchanged
bundle looks exactly like a successful one.

If the trigger is a deploy webhook, it is `bash scripts/deploy/trigger-deploy.sh refs/heads/prod`.
The webhook URL is a secret: ask the user to run the script in their own terminal, where
`DEPLOY_WEBHOOK_URL` is exported, and to paste its output. Never ask for the URL, and never put it in
a command. Never use a bare `curl` either: a webhook that expects a push payload can decline a bare
`POST` with a 3xx that deploys nothing, and `curl --fail` does not treat 3xx as a failure. The
script checks the status code, and exit 0 means accepted, not deployed.

### 3.2 Confirm the deployment is real

Run the adapter's `latest`. The newest deployment by created-at, never by position, must be created
**after** the push in 2.2, and its status must be done without an error.

- Still building → wait once, sized from this app's own recent build times, then read it again.
- Nothing newer than the push → not finished, never success. Find out why before triggering again.

A status field may not separate "building" from "healthy": a `/health` 200 during a build is the
previous container answering.

### 3.3 Smoke test

```bash
bash scripts/deploy/verify-deploy.sh --url https://<app-host>/ --since <push time from 2.2>
```

It uses the network (the live site and, for its deploy check, the GitHub API), so its permission
prompt is expected; the user approves it. Where the host does not report deployments to GitHub, add
`--skip deploy`: 3.2 is then the only deployment evidence. Every FAIL is a finding for the report.

Then exercise the change itself, not just that the process is up. When the change touches sign-in,
sessions or checkout, walk the browser pass from `/agent-core:promote` §2.3 against the live site
with a test account; after a change to third-party sign-in, start it: it must reach the provider's
account chooser, not a redirect-URI error. For anything touching CORS, test
with the **actual frontend origin**. Rejecting `evil.example` proves nothing: an origin allowlist that
is unset and falls back to a development origin rejects that too, while breaking every real browser.

---

## Phase 4 — Pay back the skipped gates

This promotion carries unreviewed code. Close the gap:

1. Finish the run log opened in 0.1: fill in every unticked box with what actually happened, and
   complete "Skipped, and why". That file is the audit trail.
2. Re-run the gates against what actually landed; nothing re-ran them on `prod` after the merge (or
   after the strip commit, where there is one):

   ```bash
   git checkout prod && git pull --ff-only origin prod
   bash scripts/check/gates.sh
   ```

3. If anything in Phase 1 was skipped rather than passed, open an issue for it now.
4. Commit the run log; an uncommitted one helps nobody:

   ```bash
   git checkout dev
   git add promote-deploy-logs/
   git commit -m "docs: log promote-deploy run" -- promote-deploy-logs/
   ```

   Then ask the user to type `! git push origin dev`, and wait for its output.

Offer `/agent-core:branch-cleanup` for the merged `internal/…` branches.

---

## Report

State plainly: that this bypassed pull request review entirely, the local gate output that stood in
for CI, the merge commits for both hops, whether and how the AI config was stripped, the env verdicts
and migrations run, and the deployment id plus timestamp proving production changed. Name every
check that was skipped rather than passed: silence here is how an unreviewed regression reaches
production unnoticed.
