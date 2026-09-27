---
description: Review the staged changes, or else the branch against its base, for a static site. Static-export safety, search metadata, accessibility, performance and Core Web Vitals, security headers and design, reported by severity; changes nothing until you pick an option at the end
argument-hint: "[base-branch]"
allowed-tools: Read, Glob, Grep, Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git fetch:*), Bash(bash scripts/check/gates.sh:*), Bash(node scripts/check/static-export.mjs:*), Bash(node scripts/check/site-audit.mjs:*), Bash(node scripts/check/bundle-budget.mjs:*)
---

# /agent-fe-nextjs-static:review

Base branch: `$ARGUMENTS` (default: the repository's default branch). The rules are `AGENTS.md`
and `.claude/rules/`; cite them in each finding.

Severity: **CRITICAL** breaks the site or exposes something now; **HIGH** breaks a numbered rule or
hurts visitors under common conditions; **MEDIUM** is defense in depth or maintainability; **LOW**
is a suggestion. CRITICAL and HIGH block the merge.

## 1. Scope

```bash
git diff --cached --stat
git fetch origin && git diff "origin/<base>...HEAD" --stat
```

Review the **staged** changes when there are any; otherwise the branch against its base. Read every
diff whole: with RTK installed, run each `git diff` as `rtk proxy git diff …`, since its rewrite
condenses a diff and a truncated diff reviews as clean.

## 2. The gates

```bash
bash scripts/check/gates.sh --hook   # staged changes
bash scripts/check/gates.sh          # a branch
```

The review cannot pass while a gate is red; report each failure with its log tail. When the diff
touches pages, content, images, fonts, `next.config` or the headers file, a build is needed too: if
one exists and is newer than the change, run `node scripts/check/site-audit.mjs` and
`node scripts/check/bundle-budget.mjs --report`; otherwise ask the user to build, and say the build
checks were not run.

## 3. Static by design (`AGENTS.md` § B)

- CRITICAL: under export mode, a `headers()`/`redirects()` in `next.config`, a proxy, or a non-GET
  route handler: each builds and then silently does nothing (`static-export.mjs` names it).
- HIGH: a request-time API, `force-dynamic` or ISR in a page; a `[segment]` without
  `generateStaticParams`; `'use client'` on a layout or a whole page.
- HIGH: app machinery added (a client data cache, a global store, an auth library, a generated API
  client) without a reason recorded in `SSOT.md`.

## 4. Search and sharing (§ C)

- HIGH: a new or changed public page without its own title and description, an absolute
  self-canonical, or a share image; hreflang alternates that are not complete and reciprocal; a
  page added to the site but not the sitemap.
- CRITICAL: anything that makes production unindexable or a preview indexable.
- For a change to metadata, sitemap, robots or JSON-LD, use the
  `agent-fe-nextjs-static:seo-validator` subagent and fold its findings in.
- When message catalogues or locale routing changed, use the `agent-fe-nextjs-static:i18n-guard`
  subagent.

## 5. Performance and Core Web Vitals (§ D)

- **LCP**: the first view's largest element is HTML text or an image with `priority`, served at the
  size it is shown; no canvas, video or client-only component stands in front of it.
- **CLS**: every image and embed has dimensions or an aspect ratio; fonts come from `next/font`
  (sized fallbacks); nothing is inserted above existing content after load (banners reserve their
  space).
- **INP**: no heavy work in event handlers; large client components and third-party scripts load
  lazily; the first-load JavaScript per page stays in budget (`bundle-budget.mjs`).
- HIGH: a raw `<img>`, a third font family, a font or script from another host without a reason, a
  new dependency that ships to the client for something CSS or the platform does.

## 6. Accessibility (§ E)

For a change to `.tsx` or styles, run the checks of `/agent-fe-nextjs-static:a11y-audit` on the
affected routes, or read for: accessible names, keyboard reach and visible focus, landmarks and
heading order, `alt` text, form labels and errors, contrast of new colour pairs, reduced motion.

## 7. Security (§ F)

For a change to `next.config`, the headers file, a form or its endpoint, a third-party script, an
env example, or anything rendering HTML, use the `agent-fe-nextjs-static:security-guard` subagent
and fold its findings in.

## 8. Design and content

Against `.claude/rules/web/design-quality.md` and `SSOT.md` § 4: tokens rather than literals, a
clear hierarchy, designed hover and focus states, real copy (no placeholders), responsive at 320 px
(`.claude/rules/web/responsive.md`).

## 9. The report

````markdown
# Review: {branch or "staged changes"}

## Status: {LGTM | Requires Changes | Blocked}

CRITICAL: {N} · HIGH: {N} · MEDIUM: {N} · LOW: {N}

## Gates and build checks

- `gates.sh`: {passed | the failures with their log tail}
- `site-audit.mjs`: {passed | failures | not run: no fresh build}

## Blocking issues

> [!CAUTION]
> **{Title}** — `{file:line}` · {rule}
> {What is wrong and what a visitor or crawler would see}
> **Fix:** {concrete fix}

## Suggestions

> [!TIP]
> **{Title}** — `{file:line}`
> {Description}
````

## 10. What to do with it

Offer three options: **apply every blocking fix**; **go through them one by one**; **stop here**.
Recommend the first when every fix is unambiguous, the second when one is a design or content
decision. Write nothing before the user picks.
