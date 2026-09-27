---
description: Accessibility audit of the .tsx files under a path, for accessible names, alt text, focus styles, keyboard traps and ARIA roles; reports findings by severity and changes nothing
argument-hint: "[path]"
---

# /agent-fe-nextjs:a11y-audit — Accessibility Audit

Path: `$ARGUMENTS` (`src/` when empty). Run it before a release. It reads and reports; fixing is a
separate request.

## 1. Machine first

Run `bun run lint` and quote what it reports under the path. `oxlint.json` (installed by
`/agent-fe-nextjs:setup`) turns on the `jsx-a11y` rules: `alt-text`, `anchor-has-content`,
`aria-props`, `aria-role`, `label-has-associated-control`, `role-has-required-aria-props`,
`interactive-supports-focus`, `no-autofocus` and `img-redundant-alt`. Do not report those findings a
second time by hand. If the repo has no `lint` script or no `oxlint.json`, say so and go on.

## 2. Read for what the linter cannot see

Scan every `.tsx` file under the path for:

- Missing `aria-label` or `aria-labelledby` on interactive elements, an icon-only button above all
- Missing alt text on images
- Missing focus styles (`outline: none` or `focus:outline-none` without a `focus-visible`
  replacement)
- Colour contrast issues: flag them for a manual check with the two colours involved; never state a
  ratio you did not compute
- Keyboard trap risks
- Missing ARIA roles on custom components

## 3. Report

One line per finding: `CRITICAL` / `WARN` / `INFO`, then `file:line` and what is wrong. End with
what needs a browser to settle (contrast, focus order, screen-reader output): jsdom and a static
read cannot.
