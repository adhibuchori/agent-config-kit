---
paths:
  - '**/providers*.tsx'
  - '**/Providers*.tsx'
  - '**/app/layout.tsx'
  - '**/app/**/layout.tsx'
  - '**/store/**'
  - 'package.json'
---

# No app machinery on a static site

Sites often start from an app template, or grow from one, and keep its machinery: a client data
cache mounted with no queries, a generated API client nothing imports, a global store for a menu
toggle, an auth library on a site with no accounts. Each one ships JavaScript to every visitor,
widens the attack surface, and misleads the next person about what the site does.

## Leave out unless the site needs it today

| Machinery | A static site uses instead |
| --- | --- |
| Client data cache (TanStack Query, SWR), GraphQL client | content read at build time in Server Components |
| Generated API client, OpenAPI tooling | the one endpoint the form posts to (`forms-on-static-hosting.md`) |
| Global store (Zustand, Redux) | `useState` in the one client component that owns the state; the URL for shareable state |
| Auth library, session handling, protected routes | nothing: a static site has no signed-in area. Accounts belong in a separate app |
| A provider wrapping the whole tree in the root layout | the provider around the one island that needs it, or nothing |

`node scripts/check/static-export.mjs` warns when the source imports one of these, and
`check:dead-code` (Knip) fails on a dependency or file nothing uses.

## When you do need one

Write down why in `SSOT.md`, mount it as low in the tree as it can go, and keep it out of the root
layout, so the pages that do not use it do not pay for it.
