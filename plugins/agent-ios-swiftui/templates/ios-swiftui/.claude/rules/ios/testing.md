---
paths:
  - '**/Tests/**'
  - 'UITests/**'
---

# Tests

How to follow AGENTS.md Rules 22 to 24. The rules themselves are stated once, in AGENTS.md.

## Logic tests: Swift Testing in the package (Rules 22 and 23)

- `@Suite` and `@Test("what it proves")`, `#expect`, and `@Test(arguments:)` for a table of
  cases; a row with three or more fields is a small `Sendable` struct.
- A test goes through the type's own `package` API: a screen model through its calls and its
  `phase`, the API through `OrdersAPI` with a canned transport. Replace only a system boundary (the
  transport, the Keychain, the clock), never a type of this app.
- Tests run in parallel in one process. Each test builds what it needs; nothing touches
  `UserDefaults.standard`, a singleton or a shared variable. A suite that cannot run in parallel
  says why: `@Suite(.serialized) // writes the one shared <thing>: <why>`.
- A test of a `@MainActor` model is `@MainActor` too.
- The expected value comes from the spec or the rule, never from running the code once.
- A test that fails sometimes is a bug to fix: the gate never retries.

## UI tests and the accessibility audit (Rule 24)

One `XCUIApplication` test per primary screen launches the app on that screen and runs the audit.
The project's default isolation is the main actor and `XCTestCase` is not, so the class opts out
and the test opts back in:

```swift
nonisolated final class AccessibilityAuditTests: XCTestCase {
    @MainActor
    func testOrderListPassesTheAudit() throws {
        let app = XCUIApplication()
        app.launch()
        try app.performAccessibilityAudit()
    }
}
```

An issue the team accepts goes through the audit's issue handler with a comment naming the issue
and the reason; the handler never returns `true` for a whole category. `/agent-ios-swiftui:a11y-audit`
runs these tests and reports each issue by screen.

On a slow CI runner the audit itself can run out of time on a long page ("Audit failed to complete
in time", XCTest's code -56). That is the tool timing out, not a finding: the test may make that one
audit once more, for that error only. Any finding fails at once, and so does a second timeout.

### What CI runs

Once the audits cover the app, the whole set outlasts a hosted macOS runner
(`.claude/anti-patterns/full-accessibility-audit-outlasts-hosted-runner.md`). The pull-request gate
then tests a CI scheme, `<App>CI`: the same app and UI test target with only the quick,
deterministic UI tests selected. The audits run on a developer's simulator,
`bash scripts/ios/app.sh ui-test` (or the test IDs of the screens a change touches), on the commit
that ships. A new UI test that is quick and deterministic joins `<App>CI`'s selected tests too.

## Coverage

`bash scripts/check/coverage.sh` runs `swift test` with coverage and fails on any file below 100%
of its lines and functions: `.claude/rules/swift/coverage.md`.
