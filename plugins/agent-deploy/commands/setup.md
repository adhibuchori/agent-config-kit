---
description: Install agent-deploy's post-deploy smoke script, the optional deploy-webhook trigger and their ask-first permissions into this repo, after a dry run you approve
argument-hint: "[--answer id=value ...]"
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Bash(git status:*), Bash(command -v agent-setup), Bash(agent-setup questions:*), Bash(agent-setup plan:*), Bash(agent-sync check:*)
---

# /agent-deploy:setup — Set Up agent-deploy In This Repo

A plugin cannot carry a repo's own scripts or permissions, so this command installs them as files:
`scripts/deploy/verify-deploy.sh` (the smoke test `/agent-deploy:verify-deploy` and
`/agent-deploy:promote-deploy` run), `scripts/deploy/trigger-deploy.sh` when the repo deploys through
a webhook, and `ask` rules so Claude asks before each run of either script, because both use the
network. Nothing is written until the user has seen the whole draft and replied **go**. Existing files
are never overwritten: the only edits to files that already exist are the managed merges the draft
lists (`.claude/settings.json`, one block each in `.gitignore` and `CLAUDE.md`).

**Arguments:** $ARGUMENTS. Each `--answer id=value` there answers that question in advance; ask only
the rest.

Every step runs in this order, and none is skipped. The engine is agent-core's `agent-setup`; the
templates path below is written out in full because the Bash tool does not export
`CLAUDE_PLUGIN_ROOT`.

## 0. Check the engine

Run `command -v agent-setup`. If it prints nothing, stop and tell the user: `agent-setup` ships in
agent-core, which this plugin depends on; install or enable it
(`/plugin install agent-core@agent-config-kit`), then run `/agent-deploy:setup` again. It needs
python3 3.8 or newer. (claude.ai and Cowork do not install plugins that have a `bin/` folder, so
agent-core, and this setup with it, runs in Claude Code.)

## 1. Explore (read-only)

Read what setup would touch, and note what you find, with the file as evidence:

- `.claude/agent-config-kit.lock`: if it already lists `agent-deploy`, stop and point the user at
  `/agent-deploy:sync`. If it has no `agent-core` entry, agent-core's layer is planned in the same
  draft.
- `.claude/OPERATIONS.md`: does § Deploys name the platform, the live URL and the four adapter
  commands? Both deploy commands read them from there. Unfilled is fine for setup; say so, because
  step 5 hands it over.
- How deploys start today: `.github/workflows/` (a deploy job on a merged pull request?), anything
  that reads `DEPLOY_WEBHOOK_URL`, and a `.github/scripts/trigger-deploy.sh` copied from a template.
  That decides the `webhook` answer. A workflow that already deploys on a merged pull request means
  `deploy-on-merge=no` (a second trigger would deploy twice); none, and a platform that deploys
  when its webhook is called, means `deploy-on-merge` is worth offering. A workflow or script that
  already strips agent config from the production branch (`strip-ai-on-pr.yml`,
  `.github/scripts/strip-ai.sh`) decides `strip-ai`; so does whether the repo has `prod` and `dev`
  branches at all.
- `scripts/deploy/`: a file already there is kept, never replaced; the draft lists it as `keep`.
- `.claude/settings.json` and `.claude/settings.local.json`: a `hooks` key that runs a
  `.claude/hooks/*.sh` script agent-core also runs is double wiring (each would run twice); setup never
  edits `hooks`, so the user removes those entries.
- `CLAUDE.md` and `.gitignore`, for the managed blocks.
- `git status --short`. If the tree is dirty, say so, and suggest committing first so the setup lands
  as a change of its own.

## 2. Ask, one question at a time

Run:

```bash
agent-setup questions --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack deploy --json
```

The list starts with agent-core's questions when this repo has no agent-core setup yet. For each
question the arguments did not answer:

- ask it on its own, with its choices;
- give the **recommended** answer and one line of why, adjusted by what step 1 found, citing the file
  (for example, `ci-cd.yml` passes `DEPLOY_WEBHOOK_URL` to a deploy step, so `webhook=yes`);
- accept "ok" as the recommended answer, and wait for the reply before the next question.

## 3. Draft

```bash
agent-setup plan --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack deploy --project "$PWD" --answer <id>=<value> ...
```

Show its output verbatim: every create, same, keep, seed, merge, conflict, block, alias, warn and lock
line, and the digest. Explain any `conflict` or `warn` line in one sentence. End with:
"Reply **go** to write exactly this."

## 4. Write only on "go"

On **go**, and only then, run `apply` with the same answers and the digest from step 3:

```bash
agent-setup apply --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack deploy --project "$PWD" --answer <id>=<value> ... --digest sha256:<hex>
```

`apply` is left out of this command's allowed tools on purpose, so the user's permission prompt is a
second, independent confirmation. Any reply other than **go** writes nothing. If `apply` exits 3, the
repo changed since the draft: go back to step 3 and show the new plan.

## 5. Verify and hand over

```bash
agent-sync check --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack deploy --project "$PWD"
```

Report its exit code and findings (0 means in sync). Then prove the scripts start without touching
the network: `bash scripts/deploy/verify-deploy.sh --help` exits 0 and lists its checks, and, when
the webhook script was installed, `bash scripts/deploy/trigger-deploy.sh` with no ref exits 2 before
any request. Expect a permission prompt for each: the new `ask` rules cover both scripts, whatever
the arguments.

Then tell the user, briefly:

- Commit the new files together with `.claude/agent-config-kit.lock`: the lock records what setup
  installed, and it is what turns the kit's hooks on for everyone who clones the repo.
- Fill `.claude/OPERATIONS.md` § Deploys (copy `.claude/OPERATIONS.example.md` if the file is
  missing): the platform, the live URL and the adapter commands `latest`, `trigger`, `read-env` and
  `backup`. `/agent-deploy:promote-deploy` stops on a placeholder it needs.
- The network is used only when a person starts it: `/agent-deploy:verify-deploy`, the smoke step of
  `/agent-deploy:promote-deploy`, or the user running a script. Nothing in the plugin's hooks does.
- `trigger-deploy.sh` reads `DEPLOY_WEBHOOK_URL` from the environment of whoever runs it. Export it in
  your own terminal only; never paste it into a prompt or commit it.
- A private repository needs `GH_TOKEN` (or a signed-in GitHub CLI) for the deploy check; the token
  goes to the GitHub API only.
