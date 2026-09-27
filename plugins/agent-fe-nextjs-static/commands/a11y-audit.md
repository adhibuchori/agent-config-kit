---
description: Accessibility audit of the built site. Runs pa11y-ci or axe in a real browser against every built page, adds the source lint and a read for what automated checkers miss, and reports findings by severity without changing anything
argument-hint: "[route ...]"
allowed-tools: Read, Glob, Grep, Bash(git status:*), Bash(node scripts/check/a11y.mjs:*), Bash(node scripts/check/static-export.mjs:*)
---

# /agent-fe-nextjs-static:a11y-audit

Routes: `$ARGUMENTS` (every built page when empty; for example `/ /contact`). It reads and reports;
fixing is a separate request. Run it before a release and after a design change.

## 1. A build to test

The audit runs against built pages, because that is what visitors get. Look for the build: `out/`
in export mode, `.next/server/app/` otherwise (`scripts/check/site.config.json` says which). If
there is none, or the source changed after it, ask the user to build (`npm run build`, or the
repo's package manager) or build it yourself if they agree, then continue.

## 2. Machine first

Run the browser check:

```bash
node scripts/check/a11y.mjs                       # every page
node scripts/check/a11y.mjs --only /,/contact     # the routes given as arguments, comma-separated
```

It serves the build on 127.0.0.1 and runs the project's own pa11y-ci (axe runner, WCAG 2 AA by
default) or axe CLI. Exit 0 is clean, 1 lists violations, 2 means it could not run: say why (no
checker installed, no browser, no build) and name the fix. Nothing is downloaded: if neither
checker is a dev dependency, say that `pa11y-ci` (brings its own browser) or `@axe-core/cli` (needs
a ChromeDriver that matches Chrome) must be added, and continue with the steps below.

Then quote what the source lint reports (`npm run lint`, from `oxlint.json`, which enables the
`jsx-a11y` rules). Do not report the same finding twice.

## 3. Read for what automated checkers miss

An automated checker finds only part of the problems. For each page in scope, read its source and,
where you can, its built HTML:

- **Keyboard**: every control is reachable with Tab in a sensible order, works with Enter or Space,
  and shows a visible focus style; menus and dialogs trap and return focus correctly; a skip link
  reaches `main`.
- **Structure**: landmarks (`header`, `nav`, `main`, `footer`), one `h1`, heading levels in order,
  lists marked up as lists.
- **Names and text**: link text that makes sense out of context (no "click here"), `alt` that says
  what the image shows or `alt=""` when it is decorative, form fields with visible labels and
  errors tied to them.
- **Motion and media**: animation stops under `prefers-reduced-motion`; video has captions when it
  carries information; nothing flashes more than three times a second.
- **Contrast**: flag pairs that look low for a manual check, with the two colours involved; never
  state a ratio you did not compute.
- **Languages**: `<html lang>` matches each page's language; a phrase in another language has its
  own `lang`.

## 4. Report

One line per finding: `CRITICAL` (blocks a task for some visitors), `HIGH`, `MEDIUM` or `LOW`,
then the route and `file:line` where it comes from, what is wrong and the fix. Group by page. End
with what still needs a person with a screen reader or a real phone: automated checks and a source
read cannot settle it.
