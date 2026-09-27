---
paths:
  - '**/*.ts'
  - '**/*.tsx'
---

# TypeScript conventions for a static site

The ban on `any` and on double assertions is `typescript/types.md`; unused code is
`typescript/dead-code.md` (both installed by agent-core's setup).

## Components

- Server Components by default. Add `'use client'` only to the leaf that needs state, an effect or
  an event handler, and pass it plain props; never mark a layout or a whole page as a client
  component.
- Content (copy, lists, links) lives in typed data files or the message catalogues, not inline in
  deeply nested JSX, so it can be reviewed and translated in one place.
- Components render. Formatting, sorting and mapping content happen in a helper next to the data,
  where a test can reach them.
- No `useMemo`, `useCallback` or `memo()` added "for performance" without a measured reason; most
  of a static site never re-renders.

## Metadata

- A page's `metadata` (or `generateMetadata`) is typed as `Metadata` from `next`, and builds its
  values from shared helpers so the title template, the origin and the Open Graph defaults exist in
  one place.
- Metadata routes (`robots.ts`, `sitemap.ts`, `manifest.ts`) return the `MetadataRoute` types and
  export `dynamic = 'force-static'`.

## Naming

| What | Convention | Example |
| --- | --- | --- |
| Component file | kebab-case file, PascalCase export | `pricing-table.tsx` → `PricingTable` |
| Hook | camelCase, `use` prefix | `useReducedMotion.ts` |
| Content and data file | kebab-case | `content/team-members.ts` |
| Folder | kebab-case | `components/site-footer/` |
| Constant | `SCREAMING_SNAKE_CASE` for true constants, camelCase for data | `MAX_TEAM_SIZE`, `teamMembers` |

## Comments

Comment the reason, not the mechanics: a comment says why a value is what it is, or what breaks if
it changes. An exported helper gets one line saying what it returns.
