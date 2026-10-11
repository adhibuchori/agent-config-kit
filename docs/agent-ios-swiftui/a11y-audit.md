# a11y-audit

Command · agent-ios-swiftui · `/agent-ios-swiftui:a11y-audit [UI test identifier]` · reads and reports · runs the UI tests on a simulator · no network

## What it does

`/agent-ios-swiftui:a11y-audit` runs the app's accessibility audit, the UI tests that call
`performAccessibilityAudit` on each primary screen, on the newest iPhone simulator without signing,
reads each issue from the result bundle, then reads the views for labels and traits the audit cannot
see, and reports every issue with its screen and the SwiftUI fix. It changes no file.

## When to reach for it

Before a release, after a UI change, or when the quality gate's UI tests fail on an audit:

```text
/agent-ios-swiftui:a11y-audit
/agent-ios-swiftui:a11y-audit OrdersUITests/AccessibilityAuditTests
```

**Not for:** a screen no UI test reaches yet, which it lists instead of auditing; add its audit test
first (the `swiftui-screen` skill does it as one of its steps). VoiceOver's reading order and the
feel of a gesture still need a person with the device.

## Prerequisites

- A Mac with Xcode 27 and an iOS simulator runtime, and the `scripts/ios/app.sh` that
  [/agent-ios-swiftui:setup](setup.md) installs.
- A UI test target whose name ends in `UITests`, with one audit test per primary screen.

## Common questions

**Why is the first run slow?**
It boots the simulator and builds the app and its UI tests; later runs reuse both and take well under a minute for one screen.

**Can the team accept an issue?**
Yes, through the audit's issue handler, with a comment that names the issue and the reason. The command reports such issues as accepted, never as fixed.

## It's working if

- The report has one line per issue: the screen, `file:line` when the view shows it, the issue type
  (contrast, Dynamic Type, hit region, element description, trait) and the fix.
- It ends with the primary screens no audit test reaches.

## Where it fits

Part of [agent-ios-swiftui](../../plugins/agent-ios-swiftui/README.md). The quality gate's macOS job runs
the same UI tests on every pull request; this command explains what they found.
