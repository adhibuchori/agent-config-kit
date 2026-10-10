---
description: Reviews the staged changes, or else the branch against origin/dev, on two axes in separate subagents, this repo's standards (the installed stack reviewer, agent-core:reviewer otherwise) and the spec the change implements (agent-core:spec-reviewer), and reports each axis apart. Reads and reports; changes nothing.
---

# /agent-core:review — Code Review

This command frames what the review looks at and in what order; two subagents do the line-by-line
passes, one per axis. Read `.claude/docs/code-review-checklist.md` first when the repo has one: it is
the human checklist around the agent, and it does not load on its own.

The two axes answer different questions. **Standards:** is the code written the way this repo's
rules say? **Spec:** does the change do what it was asked to do? Each runs in its own subagent, and
their reports stay apart: never merge them into one list or rank one axis's findings against the
other's.

## Step 1: Scope and spec

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

Find the spec, first match wins: a file or issue the user named, the plan the user approved in this
session, or the issue the branch's pull request links (`gh pr view --json body`, then
`gh issue view <number>`). With none, the spec axis reports "no spec available" and the review
goes on with the standards axis alone.

## Step 2: Start both axes

Start both subagents in the same message, on the same scope.

**Standards axis.** Use the first of these subagents that is available in this session; each knows
its stack's rules:

| Stack plugin installed | Subagent |
| --- | --- |
| agent-fe-nextjs | `agent-fe-nextjs:reviewer` |
| agent-be-hono | `agent-be-hono:reviewer` |
| agent-ai-fastapi | `agent-ai-fastapi:ai-reviewer` |
| agent-be-go | `agent-be-go:reviewer` |
| agent-be-axum | `agent-be-axum:reviewer` |
| agent-ios-swiftui | `agent-ios-swiftui:reviewer` |
| none of them | `agent-core:reviewer` (reads this repo's `AGENTS.md` and `.claude/rules/`) |

A static site (agent-fe-nextjs-static) has its own `/agent-fe-nextjs-static:review`, which checks
accessibility and Core Web Vitals as well: use it there for this axis.

**Spec axis.** `agent-core:spec-reviewer`, given the spec from Step 1.

Each brief carries the scope, the axis's one question, and these lines, word for word:

- Cite for every finding the rule it breaks (an `AGENTS.md` number or a `.claude/rules/` file) on
  the standards axis, or the spec line it rests on on the spec axis. A finding with no citation is
  left out.
- Skip what a linter, the type checker or a gate in `scripts/check/gates.list` already enforces:
  the gates decide those.
- End with the single worst finding of this axis.
- Review the scope yourself. Do not run `/agent-core:review` and do not start other subagents.

When the diff touches what a specialist owns and that specialist is installed, run it on the same
scope as part of the standards axis: `agent-fe-nextjs:i18n-guard` for user-facing strings and
message catalogues, `agent-fe-nextjs:seo-validator` for metadata, robots or share images, and
`/agent-fe-nextjs:a11y-audit` for `.tsx` that renders UI. Its brief carries the same lines.

## Step 3: Security first — block on these

Run `agent-core:security-guard` over the same diff (or the stack's own security guard, such as
`agent-docs-nextra:security-guard` or `agent-fe-nextjs-static:security-guard`, when that plugin is
installed); its findings belong to the standards axis. Whatever the stack, block on:

- Hardcoded secrets or credentials, or a real value copied into a `.env*.example` template
- SQL, shell or HTML built by string interpolation of untrusted input
- A route, handler or action that reads or writes data and never checks who is calling
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

Two sections, in this order, each holding only its own axis:

1. **Standards.** Findings from the standards subagent, security-guard, the specialists and
   Step 4, grouped CRITICAL / HIGH / MEDIUM / LOW, each with file, line, the rule it cites and the
   fix. CRITICAL blocks the merge; HIGH should be fixed before it. Close with the worst finding.
2. **Spec.** The spec reviewer's lists as it returned them (missing or partial, not asked for,
   implemented wrongly), each with the spec line it quotes, or "no spec available". Close with the
   worst finding.

Then the verdict, per axis: standards approved, approved with warnings, or blocked; spec met,
partly met, or not checked. Name any step you could not run, and list the gates you ran with their
result.

Then offer the fixes: apply all, go one by one, or leave them. Apply nothing before the user
chooses (`/agent-core:ship` applies them down to MEDIUM with no prompt).
