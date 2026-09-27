---
description: Runs this repo's quality gates, fixes each failure at its cause (never by silencing it), and re-runs until every gate passes or only a decision is left. Changes files, never commits.
argument-hint: "[files to limit format and lint to]"
---

# /agent-core:check-fix — Run the Gates, Fix at the Cause

**Arguments:** $ARGUMENTS

Use it before `/agent-core:commit` when a gate is red, or to get a messy working tree green. It
changes files and never commits or pushes.

## Step 1: Run every gate

```bash
bash scripts/check/gates.sh            # the repo's gates.list, the list pre-commit runs
bash scripts/check/gates.sh --paths <files>   # in a shared checkout: format and lint your files only
```

Give the call a timeout of at least 300000 ms. Where the repo has no `gates.sh`, run the commands
under CLAUDE.md § Quality Gates in their order. Read each failing gate's log whole.

## Step 2: Fix in this order, each at its cause

1. **Format, then lint.** Run the formatter, then the linter with its autofix; run the pair twice,
   because a linter applies some fixes only on the second pass. What remains is fixed by hand.
2. **Types.** Fix the type, not the checker: no `any`, no `as unknown as`, no `# type: ignore` or
   `@ts-expect-error` without a reason that names the tool's limitation.
3. **Build.** Run the build after a structural change: it catches resolution failures a
   type-check alone does not.
4. **Tests and coverage.** Run tests in CI's environment (the repo's `ci-env.sh` wrapper, or no env
   file at all), so a test leaning on a real credential fails here as it does in CI. Never lower a
   threshold and never exempt a file for being hard to test: delete a dead branch or test the live
   one. Integration tests that need a database run only where the repo says how.
5. **Schema.** When the schema changed, generate the migration (never hand-write one) and run the
   index-coverage check.
6. **Stack checks** (constants, i18n, payload registry, skeletons, image): fix what they name; a
   generated file is regenerated, never edited.

Never silence a finding: no lint-disable comment, no bare `# noqa`, no skipped test, no widened
allowlist to get past a gate. A narrow suppression needs a reason on the same line, and the user
agrees to it first.

## Step 3: Re-run until green

Re-run the whole gate list after the fixes; a fix in one gate can break another. Stop and ask when
the only way forward is a product decision, a contract change another repo depends on, or a
suppression.

## Step 4: Report

A table of gates with PASS or FAIL, what was fixed and where, and what remains with the reason it
needs the user. Name any file changed that this session did not write.
