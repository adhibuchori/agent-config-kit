# `wc -l` disagrees with the `max-lines` rule, and only the rule decides

**Applies to:** `oxlint.json`, which sets
`"max-lines": ["warn", { "max": 150, "skipBlankLines": true, "skipComments": true }]`
**Status:** Permanent (the flags are deliberate, so the mismatch is a property, not a bug)

## Symptom

A review lists files "over the 150-line limit" that the linter has never warned about. Both numbers
are correct. They count different things.

## Root Cause

With `skipBlankLines` and `skipComments`, the rule counts **code** lines only. In a file that
explains itself in comments, many of the physical lines do not count. Two files with the same
`wc -l` can get opposite verdicts, so `wc -l` says nothing about whether the ceiling is breached.
It only ever over-reports, so it invents work rather than hiding a violation.

## Fix

Ask the linter, which is the only thing that decides:

```bash
bun run fl:ci 2>&1 | grep max-lines   # ✅ the verdict, with the counted number
wc -l components/*.tsx                # ❌ counts blanks and comments
```

The linter names every file that breaches, with its counted number, and says nothing about the
others.

- Do not split a file because `wc -l` says so, and do not describe such a split as fixing a
  violation that never existed.
- Do not change the rule's flags to make the two numbers agree. Comments are not what makes a file
  too big.

## Scope

Bites hardest when a length audit is delegated: `wc -l` is the obvious tool for an agent asked to
check file sizes, and the wrong one. If the two flags are ever removed, the counts converge and this
file can go.
