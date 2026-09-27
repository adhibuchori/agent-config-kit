# `mock.module` is process-wide, and bun versions disagree on file order

**Applies to:** every `bun test` suite. Not to vitest, whose `vi.mock` is hoisted and scoped per
file.
**Status:** a standing trap; `bun run check:mocks` guards it.

## The trap

`mock.module` registers a replacement for the whole **process** and is never undone. A mock written
inside a test file therefore applies to every test file bun loads *after* it. Which files those are
is decided by the order bun walks the tree, and **that order can differ between bun versions** — a
laptop's bun and CI's bun need not agree.

So the failure presents as: **deterministic in CI, deterministic locally, and different.** It reads
like flake and is not. Re-running the same commit reproduces it exactly.

## Three shapes, and only one is fixable by spreading

**1. A narrowed surface.** A test replaces an auth library's `api` entry point with a factory
exporting the one function it needs. Other modules import more from that entry point, and some
call it at *module scope* — so those files stop loading entirely. Latent for as long as that test
file happens to load late.

Fix: read the real module first, then spread it.

```ts
/* Read BEFORE the registration: once installed, importing the specifier returns the mock. */
const actual = await import('<library>/api');
void mock.module('<library>/api', () => ({ ...actual, getState: async () => state }));
```

**2. A contested module.** Several test files replace the same `lib/auth/auth.ts` with disjoint
surfaces. Whichever bun loads last is the `auth` every file gets, so a service that imports `auth`
and has its own suite ends up asserting against a surface written for a different module. The
loser tests the winner's stub.

**3. A complete surface with stubbed BEHAVIOUR.** A test replaces a repository with every export
present. A sibling file then reads that file's leftover stub rather than the shared database double,
and gets the same answer for every case — including one that scripts **no rows at all**. Spreading
cannot help here; only not mocking can.

## It also causes low coverage, which is how it hides

Files can sit far under the coverage threshold **with every test passing**, next to a comment
explaining that the path is untestable because mocking a shared module would take down the run.
That reasoning is right about the mechanism and wrong about the conclusion when a shared double
already exists at preload.

So: a file that cannot be tested "because of the mocks" is a symptom of this trap, not a fact about
the code.

## The rule

Replace a module **only** from `src/test/*`, installed once at preload, steered through an exported
control object (`dbControl`, `authControl`, `providerControl`). `bun run check:mocks`
(`scripts/check/module-mocks.ts`) enforces it in pre-commit and in the quality gate. See
`.claude/test-preload.example.ts` for the shape.

**Stand a double as low as possible.** On the provider's npm package, not on the repo's wrapper
around it; on the storage client, not on a helper built from it. Then the module under test runs
for real and its own suite is still meaningful.

## The signal

A test failure whose *received* value is identical across cases that script different inputs —
especially one that scripts none. That means the steering is not being read at all, and something
else is answering the query.

Reproduce without CI: write a throwaway test that registers the suspect `mock.module` and then calls
the victim function with the shared double steered to empty. If the error string matches CI's
exactly, this is the cause.
