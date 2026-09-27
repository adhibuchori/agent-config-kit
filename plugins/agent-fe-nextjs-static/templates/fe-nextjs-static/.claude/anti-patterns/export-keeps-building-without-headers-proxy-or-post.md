# A static export builds green without its headers, proxy or form endpoint

**Applies to:** Next.js with `output: 'export'` (observed on Next.js 16.3)
**Status:** Permanent (documented: a static export has no server)

## Symptom

The site deploys and looks right, but:

- the security headers are missing from every response, although `next.config` sets them in
  `headers()`;
- the locale redirect or the header logic in `proxy.ts` / `middleware.ts` never happens;
- the contact form answers 404 or 405, although `app/api/contact/route.ts` exports `POST`.

`next build` succeeds each time. For `headers()` and for the proxy it prints a warning line among
the build output ("will not automatically work with output: export", "disables API routes and
middleware"); for the `POST` handler it prints no warning at all, and lists it as a dynamic route
in its summary.

## Root cause

A static export is files. There is no server to run `headers()`, `redirects()`, `rewrites()`, a
proxy or a request handler, so the build leaves them out instead of failing. The `out/` folder
simply has no file for the endpoint.

The loud failures are different: a metadata route without `dynamic = 'force-static'`, or a dynamic
segment without `generateStaticParams`, stops the build. Those get fixed at once; the silent ones
ship.

## Fix

- Headers and redirects go in the host's config: `public/_headers` (or the file your host reads),
  checked by `node scripts/check/security-headers.mjs`.
- Proxy work happens at build time or in the host's config.
- The form posts to a separate endpoint (`.claude/rules/web/forms-on-static-hosting.md`), or the
  site moves to `ssg-with-endpoints` mode, where route handlers run.

## How to catch it

`node scripts/check/static-export.mjs` (pre-commit) fails each of these from the source in export
mode. After a deploy, `curl -sI https://<origin>/` shows the headers the host really sends.

## Scope

Every `output: 'export'` site. It does not apply in `ssg-with-endpoints` mode, where the host runs
Next.js.
