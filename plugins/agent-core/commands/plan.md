---
description: Produces an implementation plan (scope, tasks, data, risks, open questions) before any code is written, and waits for the user to confirm it. Reads only; writes nothing.
argument-hint: "[what to build]"
---

# /agent-core:plan — Implementation Plan

**Task:** $ARGUMENTS

## Step 1: Research Before Designing

Check whether the problem is already solved: existing modules in this repo, the framework's own
docs (through Context7 when the server is available), then the wider ecosystem. Prefer extending a
proven pattern in this repo over inventing a parallel one.

## Step 2: Read The Relevant Sections

`SSOT.md` for architecture and environment facts, and `AGENTS.md` for the numbered rules (layer
ownership, the error contract), where the repo has them. The rules under `.claude/rules/` that match
the files the plan touches load when those files are read; read them now if the plan names a file
type they cover.

A stack plugin may add its own planner (for example `/agent-fe-nextjs:plan-fullstack` for a change
that spans a frontend and its API); `/agent-core:help` lists what is installed.

## Step 3: Output

```markdown
# Plan: {title}

## SCOPE
- Modules, routes or pages affected:
- Schema changes (and therefore migrations):
- Env vars added or changed:

## UNKNOWNS
- What the code did not answer, each with how to find out ("No unknowns" when there are none)

## TASKS
- [ ] [layer] [verb] [file] — what and why — ~N min

## DATA
- New tables/columns, with the indexes each foreign key needs
- Migration strategy, and whether it is reversible

## RISKS
- [HIGH/MED/LOW] risk → mitigation; only risks that could actually block or break something

## CONFIRMATION
- One to three questions that need an answer before starting, or "No blockers — ready to execute"
```

Tasks are 5 to 30 minutes each (split a larger one), ordered by what depends on what, each naming
its test at the mirrored path. Layers by stack: a frontend plans components, hooks, service hooks,
store, messages, types and validations; a docs site plans content, navigation (`_meta`), generator
scripts and config; a service that shares a schema or error codes adds a **CONTRACTS** section
naming who owns each shared shape. More than 50 tasks means phases: show phase 1 and ask before
planning the rest.

Name the branch scope the work belongs on (`internal/{scope}`, CLAUDE.md § Branching).

Do not start implementing until the plan is confirmed.
