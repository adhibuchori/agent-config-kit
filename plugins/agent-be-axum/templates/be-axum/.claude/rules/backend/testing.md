---
paths:
  - 'tests/**/*.rs'
  - 'src/**/*_tests.rs'
  - '.config/nextest.toml'
---

# Testing (Rule 25, Rule 26)

- Test through the seam the caller uses. A handler is tested with `app(state).oneshot(request)`
  in `tests/api/`, through the real router and layers; a service through its public functions; a
  repo through `#[sqlx::test]` in `tests/db/`, against a real database with `migrations/` applied.
- A unit test sits beside its source as `<name>_tests.rs`, declared at the end of the file:
  `#[cfg(test)] #[path = "<name>_tests.rs"] mod tests;`. It can reach `pub(crate)` items, and
  cargo-llvm-cov leaves it out of the coverage report.
- Mock only a system boundary: an HTTP API you call, the clock, randomness. Never replace a module
  of this crate: the test would pass against code that does not run in production.
- Expected values come from the spec or the rule, written out (`"ROUTE_NOT_FOUND"`, `422`), never
  recomputed by the code under test. An assertion carries its message (`missing_assert_message`).
- One behaviour per test, named for it: `a_body_over_the_limit_answers_413`. Write it red first,
  for the reason the missing behaviour predicts, then make it green.
- Three smells to refuse: a test that checks how the code works instead of what it does, a test
  that asserts what it just set up, and a test file per layer that never follows one request end
  to end.
- A helper outside a `#[test]` function may unwrap only in a `#![cfg(test)]` file.
- The pooler tests (`tests/pooler/`) are `#[ignore]`d and run in CI behind PgBouncer
  (`scripts/check/pooler.sh`). A change to the pool or its options runs them there.
