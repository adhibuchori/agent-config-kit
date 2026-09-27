# A hash-based CSP pasted once breaks the next build

**Applies to:** A `script-src` with `'sha256-…'` sources on a Next.js App Router site (observed on
Next.js 16.3 with `output: 'export'`)
**Status:** Permanent (how prerendered App Router pages are made)

## Symptom

The site worked after the CSP was tightened to hashes. After the next deploy, with no change to the
CSP and sometimes no change to the page either, pages render but nothing is interactive: menus do
not open, forms do not submit. The browser console lists blocked inline scripts.

## Root cause

Every App Router page carries inline scripts that hand the rendered tree to the client. Their
content is page-specific, and it contains the build ID. Without `generateBuildId` in
`next.config`, Next.js makes a new random build ID for every build, so every inline script's hash
changes on every build, even when no page changed. A hash list copied into `public/_headers` by
hand is correct for exactly one build.

The same property rules out a nonce: a nonce must be new for each request, which makes every page
render on request.

## Fix

Treat the hash list as build output, not as a hand-edited file:

1. Build, then run `node scripts/check/security-headers.mjs --print-hashes`: it prints the
   `'sha256-…'` sources each page needs.
2. Write them into the headers file the deploy ships (per page path, or merged into one list), in
   the same pipeline step as the build. When that step writes into `out/`, point `headersFile` in
   `scripts/check/site.config.json` at the generated file.
3. `node scripts/check/security-headers.mjs --verify-hashes` (part of `site-audit.mjs`) fails the
   build when any inline script would be blocked.

Setting `generateBuildId` to the commit SHA makes the hashes repeatable for one commit, but they
still change with every commit, so the steps above are still needed.

Until that pipeline exists, `script-src 'self' 'unsafe-inline'` keeps the site working, and the
check warns about it so it is not forgotten.

## How to catch it

`--verify-hashes` after every build. In the browser, a console full of CSP errors on a page that
was fine yesterday.

## Scope

Any hash-based CSP on a Next.js site. It does not apply to `'unsafe-inline'`, or to a site that
ships no inline scripts.
