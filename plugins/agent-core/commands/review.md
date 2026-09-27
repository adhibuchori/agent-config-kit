---
description: Reviews the staged changes, or else the branch against origin/dev, against this repo's rules, handing the detailed pass to the installed stack reviewer (agent-core:reviewer otherwise), and reports findings by severity. Reads and reports; changes nothing.
---

# /agent-core:review — Code Review

This command frames what the review looks at and in what order; a subagent does the line-by-line
pass. Read `.claude/docs/code-review-checklist.md` first when the repo has one: it is the human
checklist around the agent, and it does not load on its own.

## Step 1: Scope

```bash
git diff --cached --stat
git fetch origin && git diff origin/dev...HEAD --stat
```

Review the **staged** changes when there are any (`git diff --cached`): that is what
`/agent-core:commit` and `/agent-core:ship` hand you. Otherwise review the branch
(`git diff origin/dev...HEAD`; the default branch where the repo has no `dev`).

Read the diff whole. With RTK installed, run every `git diff` here as `rtk proxy git diff …`: its
rewrite condenses a diff and prints a line even for an empty one, so a truncated diff reviews as
"clean" and an empty index looks staged.

## Step 2: Pick the reviewer

Use the first of these subagents that is available in this session; each knows its stack's rules:

| Stack plugin installed | Subagent |
| --- | --- |
| agent-fe-nextjs | `agent-fe-nextjs:reviewer` |
| agent-be-hono | `agent-be-hono:reviewer` |
| agent-ai-fastapi | `agent-ai-fastapi:ai-reviewer` |
| none of them | `agent-core:reviewer` (reads this repo's `AGENTS.md` and `.claude/rules/`) |

A static site (agent-fe-nextjs-static) has its own `/agent-fe-nextjs-static:review`, which checks
accessibility and Core Web Vitals as well: use it there. Give the subagent the scope from Step 1 and
ask for its findings with file, line, rule and fix.

When the diff touches what a specialist owns and that specialist is installed, run it on the same
scope: `agent-fe-nextjs:i18n-guard` for user-facing strings and message catalogues,
`agent-fe-nextjs:seo-validator` for metadata, robots or share images, and
`/agent-fe-nextjs:a11y-audit` for `.tsx` that renders UI. Merge their findings into one report.

## Step 3: Security first — block on these

Run `agent-core:security-guard` over the same diff (or the stack's own security guard, such as
`agent-docs-nextra:security-guard` or `agent-fe-nextjs-static:security-guard`, when that plugin is
installed). Whatever the stack, block on:

- Hardcoded secrets or credentials, or a real value copied into a `.env*.example` template
- SQL, shell or HTML built by string interpolation of untrusted input
- A route, handler or action that reads or writes data without checking who is calling
- Error responses that leak internal detail (stack traces, driver or vendor messages)
- A change to the agent's own guardrails (`.claude/settings.json`, `.claude/agent-config.json`,
  `.mcp.json`, `scripts/ops/unlock.sh`, `scripts/env/`, `.github/workflows/`): a human reviews it
- A known advisory in the dependencies: run the package manager's audit on every review, not only
  when the lockfile changed, and report what it finds

Run the cheap scans first and report what they print (with RTK installed, as `rtk proxy …`):

```bash
bash scripts/check/secrets.sh                      # gitleaks over the staged changes
git diff --cached --name-only | grep -E '(^|/)\.env(\.|$)' | grep -v '\.example$'   # a real env file staged
git diff --cached | grep -nE 'eval[[:space:]]*\(|new[[:space:]]+Function[[:space:]]*\(|dangerouslySetInnerHTML|innerHTML[[:space:]]*='
git diff --cached | grep -niE "(api[_-]?key|secret|password|token|private[_-]?key)[\"']?[[:space:]]*[:=][[:space:]]*[\"'][^\"']{8,}"
```

Where the repo adopted the payload contract (`payload.config.json`), also: a new route missing
from the registry, a typed route path, a `fetch` outside the transport, or a policy edited in the
generated registry (`bun run check:endpoints` decides the last three).

## Step 4: Correctness and structure

- An async call that is not awaited; a transaction boundary that splits one logical write
- A schema change without its migration, or generated output edited by hand
- The numbered rules in `AGENTS.md` and the file-type rules in `.claude/rules/` that the diff
  touches, cited by number or file
- Errors handled explicitly, never swallowed
- Formatting, types, dead code and coverage are the gates' to fail (`bash scripts/check/gates.sh`,
  CLAUDE.md § Quality Gates): run them rather than hand-review what they already refuse

## Step 5: Report

Group findings as CRITICAL / HIGH / MEDIUM / LOW, each with file, line, the rule it breaks and the
fix. CRITICAL blocks the merge; HIGH should be fixed before it. approved, approved with warnings, or blocked. Name any step you could not run, and list the gates
you ran with their result.

Then offer the fixes: apply all, go one by one, or leave them. Apply nothing before the user
chooses (`/agent-core:ship` applies them down to MEDIUM without asking).
