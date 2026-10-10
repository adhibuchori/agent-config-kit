# Paths and commands per step

| Step | Where | Command |
| --- | --- | --- |
| Seam | the rule index `AGENTS.md`, Rules 3 and 4; `.claude/rules/ios/swiftui.md` | |
| Client | `Packages/AppCore/Sources/APIClient/<Area>API.swift`, `Tests/APIClientTests/<Area>APITests.swift` | `swift test --package-path Packages/AppCore --filter APIClientTests` |
| Red, Green, Next behaviour | `Packages/AppCore/Sources/Features/<Screen>Model.swift`, `Packages/AppCore/Tests/FeaturesTests/<Screen>ModelTests.swift` | `swift test --package-path Packages/AppCore --filter FeaturesTests` |
| View | `App/Screens/<Area>/<Screen>View.swift` | `bash scripts/ios/app.sh build` |
| Strings | `App/Localizable.xcstrings` (or the target's own catalog in a package) | `node scripts/check/i18n-catalog.mjs` |
| Audit | `UITests/AccessibilityAuditTests.swift` | `bash scripts/ios/app.sh ui-test` |
| Gates | | `bash scripts/check/gates.sh` |

Notes for the steps:

- A new target (the first screen model of an area that gets its own target) arrives with its test
  target and a row under `layers` in `scripts/check/package-graph.json`.
- The model's test is `@MainActor`, builds its own model, and replaces only the boundary the seam
  named: a closure that returns canned Domain values or throws an `AppProblem`.
- The failed phase holds a `ProblemText` (or the project's equivalent) built from the
  `AppProblem`: its catalog message, and the reference for a problem the app does not know
  (`.claude/rules/common/error-codes.md`).
- The coverage per file runs with the gates: `bash scripts/check/coverage.sh` names any file below
  100% of its lines or functions.
- A key the build extracts but the catalog lacks fails the quality gate's I4 check in CI; add it
  in the same change.
