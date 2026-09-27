# A check whose scanner matches nothing reports success

**Applies to:** Any check script: a lint wrapper, a drift check, a grep gate, a CI step that scans
files
**Status:** Permanent (a property of every scanner)

## Symptom

A new check passes on a clean tree and fails when you plant a violation, so it looks proven. Later a
real violation lands and the check still prints "all checks passed".

## Root Cause

A check has two ways to exit 0, and only one of them means anything:

- it read the files, found nothing wrong, and passed;
- it read **nothing**, and passed. Its pattern stopped matching the real syntax, its glob points at
  a folder that moved, or its file list came back empty.

Both print the same line. A red-then-green test does not tell them apart either: the planted
violation often matches only because whoever planted it wrote it in the shape the pattern expects.
A pattern that requires call sites to end in `\n));` when every real one ends in `\n}));` matches
none of them, and a check that prints the size of its allowlist makes that look like a count of what
it saw.

## Fix

1. **Assert the scanner saw what you know is there.** If the check has an allowlist, fail when an
   allowlisted entry is never observed. A pattern that stops matching then leaves its row unseen,
   and the check goes red.
2. **Fail on an empty corpus.** Zero files read means the check could not run, not that the repo
   is clean. A sparse checkout, a moved folder and a filter that stopped matching all look like
   success otherwise.
3. **Match the call site narrowly, then parse.** Find where the call starts with a short pattern,
   and read its arguments by balancing brackets from there, instead of guessing the whole shape in
   one regular expression.
4. **Print what was scanned, not what was configured:** `scanned <n> files` tells you the check ran;
   `1 allowed entry` tells you nothing.

## Signal

A check that has only ever failed on a violation you wrote to test it. Before trusting it, ask: if
the thing it looks for moved out of the pattern's reach, would it still say "passed"? If yes, add
(1) or (2) until the answer is no.
