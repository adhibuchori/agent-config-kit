# Why the lint and format configs say what they say

`oxlint.json` and `.oxfmtrc.json` are plain JSON, so they carry no comments. The reasons behind
their choices live here. Both files are yours to edit: setup creates them once, and
`/agent-fe-nextjs-static:sync --check` never reports your edits as drift.

## oxlint.json

The lint for a static Next.js site. Accessibility, images and injection are errors, because each
is a class of bug a visitor meets.

| Rules | Why |
| --- | --- |
| `react/no-danger` | `.claude/rules/web/security.md`: JSON-LD renders as a script child, never through `__html`. |
| `jsx-a11y/*` | Built pages are checked in a browser by `scripts/check/a11y.mjs`; these rules catch the same problems in the source, before a build. |
| `nextjs/*` | `.claude/rules/web/performance.md`: images through `next/image`, fonts through `next/font`, third-party scripts through `next/script`. |
| `no-console` off under `scripts/**` | Check scripts print for a person at a terminal. |

## .oxfmtrc.json

`scripts/check/folder-shape.mjs` is in `ignorePatterns`: agent-core's setup installs it and
`/agent-core:sync --check` compares it with the plugin's copy, so a format pass here would show as
drift.
