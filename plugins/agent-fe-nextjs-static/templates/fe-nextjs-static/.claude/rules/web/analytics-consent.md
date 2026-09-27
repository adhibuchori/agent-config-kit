---
paths:
  - '**/app/layout.tsx'
  - '**/app/**/layout.tsx'
  - '**/*analytics*'
  - '**/*consent*'
  - '**/*cookie*'
  - 'public/_headers'
---

# Analytics and consent

Analytics on a company site is usually one script tag, and it is where most of the site's privacy
and performance risk sits: it runs on every page, for every visitor, from someone else's server.

## Choose

- Prefer a privacy-friendly, cookieless analytics product, or self-hosted analytics, when the
  questions are "how many visits, from where, to which page". Record the choice and the reason in
  `SSOT.md`.
- What needs consent depends on the visitors' jurisdiction and on what the tool stores or reads on
  the device. Decide with whoever owns legal questions; this rule does not decide it for you.

## Load

- Only in production builds: never in development or preview (gate on the same build-time variable
  that makes previews `noindex`), so tests and reviewers do not pollute the numbers.
- Through `next/script` with `strategy="afterInteractive"` or `lazyOnload`, never a blocking
  `<script>` in the head.
- Where consent is needed, the script is not loaded (not merely told to stay quiet) until the
  visitor agrees, and a refusal is as easy as an agreement: the same size and the same number of
  clicks.
- Its exact origins are in the CSP (`script-src`, `connect-src`, and `img-src` if it uses a pixel),
  and nowhere wider.

## Respect

- A consent choice is remembered and can be changed from every page (a link in the footer).
- No personal data in event names or properties: no email addresses, no form contents, no full
  URLs with query strings that carry them.
- The privacy page names each tool, what it collects and why, and it is linked from the footer and
  from the consent banner.
