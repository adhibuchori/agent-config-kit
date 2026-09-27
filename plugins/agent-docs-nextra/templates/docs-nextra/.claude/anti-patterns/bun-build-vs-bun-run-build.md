# `bun <name>` ≠ `bun run <name>`, for `build` and for `test`

**Applies to:** Any Bun project
**Status:** Permanent (intentional Bun CLI design)

## Symptom

**`build`:** `bun build` prints bundler output or errors instead of running the `build` script in
`package.json`.

**`test`:** `bun test` reports many failures that do not exist. In a Vitest suite, about half the
tests can fail under `bun test` while `bun run test` passes every one, all with the same error:

```text
TypeError: vi.mocked is not a function
```

The `test` case is the more dangerous of the two. A wrong bundler call fails loudly; false test
failures look exactly like a regression, and someone "fixes" working code chasing them, or decides
the suite is flaky and stops trusting it.

## Root Cause

`build` and `test` are both **native Bun subcommands**. They never look at `package.json`.
`bun test` runs Bun's own test runner, which does not implement Vitest's API (`vi.mocked`,
`vi.stubEnv`, …), so every Vitest-specific call throws.

To run a script defined in `package.json`, say `bun run <script>`.

## Fix

```bash
bun run build      # ✅ runs package.json "build"
bun run dev        # ✅ runs package.json "dev"
bun run type-check # ✅ runs package.json "type-check"

bun build          # ❌ invokes Bun's native bundler
bun test           # ❌ invokes Bun's native test runner
```

This docs site has no test suite, so the `test` case bites when the same habit reaches a repository
that has one. If CLAUDE.md lists `bun build` as shorthand anywhere, treat that as a typo and always
include `run`.

**Before believing a mass failure:** when dozens of failures share one error message, check the
command before the code.

## When to revisit

Never — this is intentional Bun CLI design.
