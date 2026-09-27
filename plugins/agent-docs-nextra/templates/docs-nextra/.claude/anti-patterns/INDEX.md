# Anti-Patterns Index

> Lazy-loaded knowledge base. Load only the file(s) matching your current task.
> Each file is self-contained — root cause + fix + scope.

## Loading Guide

| Trigger / Task                                                              | Load                                                  |
| --------------------------------------------------------------------------- | ----------------------------------------------------- |
| Nextra setup, build, or upgrade                                             | nextra-zod-v4-bug.md, nodejs-25-webstorage-ssr.md     |
| Local Next.js dev/build on Node.js 25+                                      | nodejs-25-webstorage-ssr.md                           |
| Any `bun build` or `bun test` invocation, or a mass test failure            | bun-build-vs-bun-run-build.md                         |
| Generated pages differ after a format run, or regenerate with a diff        | oxfmt-rewrites-generated-files.md                     |
| A file reported over the line limit that the linter never flagged           | max-lines-skips-blanks-and-comments.md                |
| Writing or trusting a check script, grep gate or drift check                | a-check-that-matches-nothing-passes.md                |
| A PR with no checks, or a merge that ran nothing; writing a commit or PR    | commit-message-skip-ci-substring.md                   |
| Staged files you did not stage, or a commit carrying someone else's work    | shared-git-index-across-sessions.md                   |
| Building or applying a patch; files deleted after `git apply`               | git-apply-check-passes-then-deletes.md                |

## When to add a new entry

A new anti-pattern qualifies when:

- It cost real debugging time (>30 min)
- The root cause is non-obvious from reading code/docs
- Same trap is likely to recur (vendor bug, environment quirk, tooling gotcha)

If the bug gets fixed upstream, **delete the file** and its row here — don't leave stale entries.
Every row names a file that exists, and every file here has a row.

## File naming convention

`<scope>-<short-description>.md` — kebab-case, descriptive enough to skip without opening.

Examples:

- `nextra-zod-v4-bug.md`
- `nodejs-25-webstorage-ssr.md`
- `bun-build-vs-bun-run-build.md`
