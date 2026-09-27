# Nextra 4.6.x — Zod v4 LayoutPropsSchema bug

**Applies to:** any Nextra docs repo, pinned to `nextra@4.5.1` / `nextra-theme-docs@4.5.1`
**Status:** Pending upstream fix

## Symptom

Build fails on any nested content page:

```text
✖ Invalid input: expected nonoptional, received undefined
  → at children
```

The error carries a numeric digest (a different one in prod and in dev). Stack trace is hidden inside Next.js runtime; the actual page content renders successfully in the RSC payload, but the `Layout` wrapper then throws.

## Root Cause

`LayoutPropsSchema` in `nextra-theme-docs@4.6.x` includes `children` as required via `z.custom()` inside `z.strictObject()`. But the `Layout` component destructures `children` out before calling `LayoutPropsSchema.safeParse(themeConfig)` — so `children` is always missing from the parse input. Zod v4 `strictObject` rejects with the nonoptional error.

```js
// node_modules/nextra-theme-docs/dist/layout.js — the bug
({ children, ...themeConfig } = t0);
const { data, error } = LayoutPropsSchema.safeParse(themeConfig); // children stripped!
if (error) throw z.prettifyError(error); // always throws
```

## Fix

Pin both packages to exactly 4.5.1 (before the Zod v4 migration) in `package.json`, with no range:

```json
{
  "dependencies": {
    "nextra": "4.5.1",
    "nextra-theme-docs": "4.5.1"
  }
}
```

Do not bump either package without checking the Nextra changelog first — see "When to revisit" below.

## When to revisit

Check Nextra changelog for fix. Test upgrade by running `next build` on a docs project with at least one nested route (e.g., `/<section>/<page>`). If build succeeds with 4.6.x or later, delete this file and bump both packages together.
