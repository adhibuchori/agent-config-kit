---
paths:
  - '**/*form*.tsx'
  - '**/*Form*.tsx'
  - '**/contact/**'
  - '**/newsletter/**'
  - '**/app/api/**'
  - '**/actions.ts'
---

# Forms on a static site

A contact or newsletter form is the one place a static site takes input from strangers. It fails in
three ways: it posts to an endpoint that was never deployed, it becomes a spam relay, or it leaks
what visitors typed.

## Where the endpoint lives

- `export` mode: this app has no server, so a `POST` route handler builds and then does not exist
  (`static-export.md`). The form posts to a **separate** endpoint: a serverless function on the
  host, a small service of your own, or a form service. Its origin goes in the CSP (`form-action`
  for a plain `<form>`, `connect-src` for `fetch`) and in `SSOT.md`.
- `ssg-with-endpoints` mode: one route handler per form under `app/api/` (the `endpoints` globs).
- The endpoint's secrets (a mail provider key, a list id) live only where the endpoint runs, never
  in a `NEXT_PUBLIC_` variable.

## The form

- A real `<form method="post" action="…">` with labelled fields and native constraints
  (`required`, `type="email"`, `maxlength`), so it works before and without JavaScript. Script adds
  inline feedback on top.
- The result is announced: a status region with `aria-live="polite"`, focus moved to the first
  invalid field on error.
- Say what happens to the data, next to the button, with a link to the privacy page. A newsletter
  sign-up is double opt-in.

## The endpoint

- Validate every field on the server with a schema and length limits; the browser's checks are a
  convenience, not a control. Reject unknown fields.
- Anything that reaches a mail header (subject, name, reply address) has CR and LF removed. The
  visitor's address goes in `Reply-To`, never in `From`.
- Answer with a generic message and a status code; never echo a stack trace or the provider's
  error.
- In export mode the endpoint is on another origin: it allows exactly the site's origin in CORS
  and answers the preflight, nothing wider.
- Log an id and the outcome, never the message body or the address.

## Spam

- A honeypot field that people cannot reach (hidden with CSS, `tabIndex={-1}`,
  `autoComplete="off"`, `aria-hidden`), rejected on the server when filled, plus a minimum time
  between page load and submit.
- A rate limit per client that holds across instances: a shared store, or the host's own
  rate-limiting. A counter in the function's memory does not
  (`.claude/anti-patterns/in-memory-rate-limit-on-serverless.md`).
- A challenge (CAPTCHA-style) only when the two above are not enough; its origins then go in the
  CSP, and it is named on the privacy page.

## Before launch

Submit the real form on the deployed site, from a phone, and confirm the message arrives. The build
checks cannot see an endpoint on another origin.
