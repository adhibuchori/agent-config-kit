# The formatter rewrites generated files unless it ignores them

**Applies to:** Every folder a generator writes: the pages `docs:generate` and `changelog:generate`
produce under `content/`, and any generator added later
**Status:** Permanent (the formatter works as configured)

## Symptom

A generator runs clean, and its output matches what it would write again. Then the format step
runs, and every generated file differs from what the generator writes. Re-running the generator
puts them back until the next format run: a loop with no error from either tool, and a diff on every
regeneration that nobody asked for.

## Root Cause

`oxfmt --write` rewrites every file it can format inside its scope, Markdown and its YAML
frontmatter included. One changed quote style is enough: a generator that detects staleness by
comparing bytes now sees a difference in every file it owns.

## Fix

Keep generated folders in the formatter's ignore list (`ignorePatterns` in `.oxfmtrc.json`), beside
the build output:

```json
"ignorePatterns": ["node_modules/", ".next/", "content/", "scripts/"]
```

Do **not** make the generator emit whatever the formatter prefers instead. That makes the
formatter's config the spec for the generated output, and any config change silently breaks the
generator.

## How to catch it

Test the interaction in this order. The first line alone passes and proves nothing:

```bash
bun run docs:generate && git diff --exit-code -- content/   # clean
node_modules/.bin/oxfmt --write .                           # format everything
git diff --exit-code -- content/                            # must still be clean
```

## Scope

Any generator. Add its output folder to the ignore list in the same change that adds the generator.
