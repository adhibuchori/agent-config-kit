---
paths:
  - 'src/**/*.rs'
  - 'tests/**/*.rs'
  - 'scripts/check/coverage-exempt.txt'
  - 'scripts/check/coverage.sh'
---

# COVER: coverage in Rust (Rule 25)

- `scripts/check/coverage.sh` runs every test under `cargo llvm-cov nextest` and holds each file
  to 100% of its lines and functions (`coverage-per-file.mjs`). Branch coverage needs a nightly
  compiler and would report nothing on stable, so it is not counted.
- A function counts once it ran; an `async fn` and every closure count as functions of their own,
  so a closure on an error path needs the test that takes that path.
- A file nobody tests is reported at 0%, so it fails until it has a test.
- The database tier is part of the run: `#[sqlx::test]` needs PostgreSQL at `DATABASE_URL`.
- An exemption is one line of `scripts/check/coverage-exempt.txt`, `<glob>  # <reason>`, and only
  for a composition root (`src/main.rs`, `src/bin/`) or generated code. Code that is hard to test
  gets a seam and a test, never an exemption.
- `#[coverage(off)]` is unstable; never reach for `cfg(coverage_nightly)` to hide a file.
