---
paths:
  - 'Packages/**/*.swift'
  - 'scripts/check/coverage-exempt.txt'
  - 'scripts/check/coverage.sh'
---

# Coverage of the Swift logic package

How to follow AGENTS.md Rule 22. The rule itself is stated once, in AGENTS.md.

- `bash scripts/check/coverage.sh` runs `swift test --enable-code-coverage` for every package
  under `Packages/`, exports `coverage/lcov.info` with `xcrun llvm-cov export -format=lcov`, and
  fails on any file below 100% of its lines or of its functions. A closure is a function to
  llvm-cov, and so is the right side of `??`: a test reaches both sides.
- Never read Xcode's coverage report (`xccov`) for this: it leaves Swift package files out and
  reports 100% while llvm-cov reports half
  (`.claude/anti-patterns/xccov-omits-package-files.md`).
- A library target no test target depends on is missing from the report instead of reported at
  0%; `scripts/check/package-graph.sh` fails it first (P3).
- The app target, its views and the UI tests are outside the floor, as views are on the web: keep
  them thin (`.claude/rules/ios/swiftui.md`) and their logic in the package.
- `scripts/check/coverage-exempt.txt` leaves a file out only for one of two reasons, written on
  its line as `# generated: <why>` or `# composition root: <why>` (a file that only wires real parts
  together); `scripts/check/coverage-policy.mjs` refuses any other. An untested branch is never a
  reason; write the test.
- Under `scripts/check/ci-env.sh` the run sees CI's variables only, so it uses the Xcode that
  `xcode-select` names; `coverage.sh` prints which one.
