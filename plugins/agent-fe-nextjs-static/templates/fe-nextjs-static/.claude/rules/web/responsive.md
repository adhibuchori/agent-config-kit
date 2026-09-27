---
paths:
  - '**/*.tsx'
  - '**/*.css'
---

# Responsive layout

The width a page is read at is an input, not an assumption. Most visitors to a company site arrive
on a phone, from a shared link. These rules are not machine-checked; review reads them, and the
launch checklist measures overflow in a real browser.

## Rules

- **R1** Breakpoints have names, declared once (in Tailwind v4, `--breakpoint-*` in `@theme`, in
  rem), and media queries use the names. No pixel literals scattered across files.
- **R2** Mobile first: the base style is the narrow layout; wider layouts are added with min-width
  queries.
- **R3** A fixed width of 200 px or more carries a fluid guard: `width: min(360px, 100%)` or
  `max-width: 100%`. A grid track of that size is wrapped in `min()`:
  `repeat(auto-fill, minmax(min(18rem, 100%), 1fr))`.
- **R4** Type and large spacing scale with `clamp()` between a phone and a desktop value, not with a
  jump at one breakpoint.
- **R5** Nothing overflows the viewport horizontally at 320 px. A wide element (a table, a code
  block, a logo strip) scrolls inside its own `overflow-x: auto` wrapper, and that wrapper is
  `position: relative` so an absolutely positioned child cannot widen the page.
- **R6** Touch targets are at least 24 by 24 CSS pixels with space around them (WCAG 2.2 AA), and
  44 by 44 for primary actions such as the call to action and the menu button.
- **R7** Media keeps its aspect ratio (`aspect-ratio`, or `width` and `height` on the image) so the
  page does not shift while it loads.
- **R8** Every section root is responsive by some mechanism: a width query, `clamp()`/`min()`/
  `minmax()`, or a fluid unit. A section with none of them was only ever looked at on one screen.

## Checking it

Open the built site at 320, 375, 768, 1024 and 1440 px wide. At each width,
`document.documentElement.scrollWidth` must equal `clientWidth` (no horizontal scroll), and nothing
may be clipped or overlap. Record the widths you checked in the pull request.
