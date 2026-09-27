# A check whose scanner matches nothing reports success

**Applies to:** every guard script under `scripts/check/` — anything that scans files and exits 0
when it finds no violation.
**Status:** a standing trap; kept as the checklist for writing a new guard.

## The trap

A check script has two failure modes, and only one of them is loud:

- It finds a violation and exits 1. Visible.
- It finds **nothing to look at** and exits 0. Indistinguishable from a clean repo.

Take a guard against per-file `mock.module` calls written with this pattern:

```ts
const CALL = /mock\.module\(\s*['"]([^'"]+)['"]\s*,([\s\S]*?)\n\)\);/g;
```

The tail `\n\)\);` requires a newline followed by `));`. Real factories end `\n}));`. The regex
matches **zero** call sites across the whole test tree, and the script prints
`Module mocks: 1 allowed replacement(s), all checks passed` — because that count comes from the
allowlist's `.size`, not from anything observed. A deliberately reintroduced violation passes. A
violation written as a test injection can still be caught, but only when it happens to be
formatted to fit the broken pattern.

## Why a test does not catch it

Verifying a check by making it **fail** (inject a violation → red) and by confirming green on a
clean tree passes both ways. Neither step can distinguish "scanned and found nothing wrong" from
"scanned nothing". A red-then-green pair is not enough when the green can be vacuous.

## The fixes, in order of value

**1. Make silence impossible — assert the scanner saw what you know is there.** The strongest guard
is an invariant that fails when the scan finds less than it must. For the mock guard that is: every
allowlisted entry must actually be observed.

```ts
for (const [key, reason] of ALLOWED) {
  if (seen.has(key)) continue;
  failures.push(`${key} is allowlisted but no such call was found …`);
}
```

If the scanner stops matching, the allowlist row goes unseen and the check fails. An empty allowlist
loses this protection, so pair it with (2).

**2. Fail on an empty corpus.** Zero files is the check unable to run, not a clean result. A sparse
checkout, an uninitialised submodule, or a filter that stopped matching all look like success.

```ts
if (testFiles.length === 0) {
  console.error('✗ no test files under src/ — the rule cannot be verified.');
  process.exit(1);
}
```

The same holds for a filesystem test: assert first that the walk found what it expected, or a test
that matches nothing passes by vacuum.

**3. Do not guess at syntax with one pattern.** A factory ends `}))`, `})`, or `});` depending on how
it was written. Find the call site with a narrow pattern, then read its arguments by balancing
parentheses from there:

```ts
const CALL = /mock\.module\(\s*['"]([^'"]+)['"]/g;      /* the call site only */
function factoryAfter(content: string, index: number): string { /* paren-balance */ }
```

**4. Print what was scanned, not what was configured.** `scanning <n> test file(s)` is useful;
`1 allowed replacement(s)` is the allowlist size and says nothing about the run.

## The signal

A check that has never failed on a real violation, only on one you wrote to test it. Before trusting
a new guard, ask: **if the thing it looks for vanished from my regex's reach, would it still say
"passed"?** If yes, add rule (1) or (2) until the answer is no.

The same shape hides in shell. A `grep -v '\.repository\.ts'` over the `+` lines of a diff can
never see the file name a line came from, so an exemption meant for one kind of file matches
nothing: the check flags the files it meant to allow, and reads as if it works. Filter by path
before reading lines (`git diff -- ':!*.repository.ts'`), then test the exemption with a file it
must allow.

A pipe can make a scan read less than it must. Under `set -o pipefail`, `git diff | grep -q` lets
`grep` exit at the first match; on a diff larger than the pipe buffer `git diff` then dies of
`SIGPIPE`, the pipeline fails, and the `if` reads that as "no match". Read the whole input first (a
file or a variable, then `grep`), and prove the check on an input larger than the pipe buffer.
