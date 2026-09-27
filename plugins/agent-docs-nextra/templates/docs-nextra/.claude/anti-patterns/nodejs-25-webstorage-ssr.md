# Node.js 25 — Broken localStorage breaks Next.js SSR

**Applies to:** Any local Next.js dev/build on macOS with Node.js 25+
**Status:** Permanent (workaround required)

## Symptom

SSR crashes with:

```text
TypeError: localStorage.getItem is not a function
```

Often shows as `unhandledRejection` repeated multiple times. Triggered by `next-themes` (used by `nextra-theme-docs`, shadcn theme provider, etc.) or any library that touches `localStorage` during render.

Companion warning that confirms the diagnosis:

```text
Warning: `--localstorage-file` was provided without a valid path
```

## Root Cause

Node.js 25 enables `--experimental-webstorage` by default. It injects a `localStorage` global, but the implementation is incomplete — methods like `.getItem` / `.setItem` are `undefined` when `--localstorage-file` isn't set to a valid path. The standard SSR guard fails too:

```js
if (typeof window === 'undefined') return; // ❌ Node.js 25 injects `window` global
const value = localStorage.getItem('theme'); // 💥 .getItem is undefined
```

## Fix

Start Next.js through `scripts/next/run.mjs`. It adds `--no-experimental-webstorage` on Node 25 and
later only, because a Node version that does not know the flag refuses it with
`node: bad option`. `dev` and `build` both go through it:

```json
{
  "scripts": {
    "dev": "bun run scripts/next/env.ts check development --soft && node scripts/next/run.mjs dev",
    "build": "bun run scripts/next/env.ts check production --soft && node scripts/next/run.mjs build && pagefind --site .next/server/app --output-path out/_pagefind"
  }
}
```

Passing the flag unconditionally instead breaks every machine and CI runner whose Node predates it,
such as Node 20.

## When to revisit

When Node.js fixes the broken localStorage implementation, or when `next-themes` adds a stronger SSR guard (e.g., checking `typeof localStorage.getItem === 'function'`). Test by running `next build` directly, without the wrapper, on Node 25 or later. If it passes, the wrapper can go.
