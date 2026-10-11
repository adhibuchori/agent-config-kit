# `file_length` counts blank and comment lines unless told not to

**Applies to:** SwiftLint `file_length` (AGENTS.md Rule 15)
**Status:** Permanent (the rule's default)

## Symptom

Two numbers disagree. `wc -l` says a file is over 150 lines while SwiftLint passes it, or a
well-commented file fails while its code is short. Files get split to fix a count no rule meant.

## Root cause

By default `file_length` counts every line, blank and comment lines included. The limit here is
150 **code** lines, like the kit's `max-lines` with `skipBlankLines` and `skipComments`, so
`.swiftlint.yml` sets `ignore_comment_only_lines: true`: a blank or comment-only line is then never
counted. Measured on fixtures with SwiftLint 0.65: ten code lines plus ten blank or ten comment
lines count 20 by default and 10 with the option.

## Fix

Ask the gate, which is the only thing that decides:

```bash
swiftlint lint --quiet          # the gate: names each file over the limit, with its count
wc -l App/Screens/**/*.swift    # counts blanks and comments; never the measure
```

Keep the option on: dropping it would penalise exactly the comments the repo asks for.

## Scope

Every Swift file SwiftLint reads.
