# `panic = "abort"` turns CatchPanicLayer off in production, and no test notices

**Applies to:** a release profile with `panic = "abort"` in front of tower-http's `CatchPanicLayer`
**Status:** A standing trap; `cargo-policy.sh` refuses `panic = "abort"`

## Symptom

One request that hits a bug ends the whole process: every request in flight fails, the
orchestrator restarts the service, and the logs show no 500, only a restart. Every test passed,
including the one proving that a panic answers 500.

## Root Cause

`panic = "abort"` terminates the process on panic, so there is no unwinding for the layer to
catch, and "tests ignore the `panic` setting" (Cargo book, profiles): the test that proves the
500 runs with unwinding. Release builds also wrap integer overflow where tests panic, unless
`overflow-checks = true`.

## Fix

Keep `panic = "unwind"` and `overflow-checks = true` in `[profile.release]`, as the starter sets.

## When to revisit

If a binary size limit forces `abort`, CatchPanicLayer has to go with it, and the restart policy
becomes the error handling: decide that on purpose.
