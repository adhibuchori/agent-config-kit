---
paths:
  - 'next.config.*'
  - 'public/_headers'
  - '**/*.conf'
  - '**/app/**/route.ts'
  - '**/*.tsx'
  - '.env*.example'
---

# Security for a static site

A static site has little to attack, which makes the few mistakes cheap to spot and expensive to
miss: a header that never ships, a secret in a public variable, an injected script. Reading `.env*`
files goes through `scripts/env/show.sh` and the unlock in `docs/unlock.md`.

## Headers live where the host reads them

- Under `output: 'export'`, `headers()` in `next.config` is ignored (the build only warns). The
  headers belong in the host's own config: `public/_headers` by default (the format several static
  hosts read: a path line, then indented `Name: value` lines), or the host's nginx or platform file.
  `headersFile` in `scripts/check/site.config.json` names it, and
  `node scripts/check/security-headers.mjs` checks it.
- Every page gets: `Content-Security-Policy` with `object-src 'none'`, `base-uri 'self'` and
  `frame-ancestors 'none'`; `Strict-Transport-Security` with `max-age` of a year or more
  (`includeSubDomains` only when every subdomain is served over HTTPS); `X-Content-Type-Options:
  nosniff`; `Referrer-Policy: strict-origin-when-cross-origin`; a `Permissions-Policy` that turns
  off what the site does not use; `Cross-Origin-Opener-Policy: same-origin`.
- The file proves intent, not delivery. After each deploy, read the live response
  (`curl -sI https://<origin>/`); `/agent-fe-nextjs-static:launch-checklist` does this.

## A CSP that works with prerendered pages

- A **nonce** CSP needs a fresh nonce per request, so it makes every page render on request: it
  does not fit a static site. Use **hashes**.
- Every Next.js page carries inline scripts, and their content changes with the page and with each
  build. Start with `script-src 'self' 'unsafe-inline'` (the check warns while it is there), then
  move to hashes once the pages are stable: `node scripts/check/security-headers.mjs --print-hashes`
  lists what each page needs, and `--verify-hashes` (in `site-audit.mjs`) fails any inline script
  the policy would block, which is a page that no longer hydrates.
- Never `'unsafe-eval'`, never a scheme or `*` as a script source, never `connect-src *`. A third
  party gets its exact origin in the one directive it needs, with a comment saying why.
- A form that posts to another origin needs that origin in `form-action` (a plain `<form>`) or
  `connect-src` (`fetch`).

## In the code

- No `dangerouslySetInnerHTML` (the linter refuses `react/no-danger`). JSON-LD renders as a script
  child with `<` escaped (`seo.md`); rich text comes from a renderer that escapes.
- A URL from content or a CMS goes into `href`/`src` only when its scheme is `https:`, `http:`,
  `mailto:` or `tel:`. `target="_blank"` carries `rel="noopener noreferrer"`.
- `NEXT_PUBLIC_*` is compiled into the pages and readable by anyone. Only public values (the site
  origin, a public analytics id) use it; a secret never does, and the build output is public.
- A third-party script comes from an exact, named origin, loads through `next/script`, and is listed
  in the CSP. Where the provider publishes a versioned file, pin it with `integrity`.
- No source maps in the public output (`productionBrowserSourceMaps` stays off).
- Endpoints (`ssg-with-endpoints` mode, or the separate form endpoint) validate every field on the
  server; see `forms-on-static-hosting.md`.
