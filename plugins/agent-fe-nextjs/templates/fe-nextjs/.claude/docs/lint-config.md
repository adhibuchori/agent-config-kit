# Why the lint and format configs say what they say

`oxlint.json` and `.oxfmtrc.json` are plain JSON, so they carry no comments. The reasons behind
their choices live here. Both files are yours to edit: setup creates them once, and
`/agent-fe-nextjs:sync --check` never reports your edits as drift.

## oxlint.json rules

| Rule | Why |
| --- | --- |
| `typescript/no-explicit-any` | AGENTS.md Rule 31, in tests too. |
| `import/no-cycle` | SSOT.md §4.1 declares the layer map. The import plugin, this rule and the `no-restricted-imports` overrides below are what make its arrows real. |
| `import/no-unassigned-import` off | A stylesheet or a polyfill is imported for its side effect and has nothing to assign. |
| `max-lines` (150, an error) | AGENTS.md Rule 27. An error, not a warning: a warning lets a file sit over the limit and commit clean. |

## oxlint.json overrides

| Files | Why |
| --- | --- |
| `src/components/**` | AGENTS.md Rules 6 and 32: a component renders; it never reaches for data or global state itself. Each of these arrives through a named hook, which is also what makes it testable without rendering. Rule 14 covers the generated client specifically. |
| `src/lib/**` | SSOT.md §4.1: utilities are pure and sit below everything. The dependency direction never reverses, which is what lets a hook import a helper without dragging a component with it. |
| `src/hooks/**` | AGENTS.md Rule 7: a hook may import lib, store and types, never a component. |
| `src/testing/**`: `no-await-in-loop` off | A test awaits one step after another on purpose: a render, then an event, then its result. |
| `scripts/**`: `unicorn/no-array-sort` off | `[...x].sort()` rather than `toSorted()`, so the checkers also run where the tsconfig lib stops at ES2022. |
| `scripts/**`: `max-depth` off | These walk nested trees: directories, then files, then matches within a file. The nesting is the shape of the data, not a tangled branch in application logic. |

## .oxfmtrc.json

`scripts/check/coverage-policy.mjs` and `scripts/check/folder-shape.mjs` are in `ignorePatterns`:
the plugins install them and `sync --check` compares them with the plugins' copies, so a format
pass here would show as drift.
