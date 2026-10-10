---
description: Runs this iOS app's accessibility audit (the UI tests that call performAccessibilityAudit on each primary screen) on a simulator, then reads the views for labels and traits, and reports each issue with its screen and fix. Reads and reports; changes no file.
argument-hint: "[UI test identifier, such as OrdersUITests/AccessibilityAuditTests]"
---

# Accessibility audit

Scope: `$ARGUMENTS` (a UI test target, class or test; every UI test target when empty). It runs
the audit and reports; fixing is a separate request.

1. **Run the audit.** Run `bash scripts/ios/app.sh ui-test $ARGUMENTS`. It builds for the newest
   iPhone simulator without signing, runs the UI tests, and prints each failed test with the
   audit's message, then the path of the result bundle. The first run boots the simulator and can
   take several minutes.
   Done when it has printed its `app: tests` line and the result bundle path.
2. **Read each issue.** For every failed audit test, read its activities from the result bundle:
   `xcrun xcresulttool get test-results activities --test-id "<test id>" --path <bundle>`. Each
   issue names its type (contrast, Dynamic Type, hit region, element description, trait) and the
   element it found.
   Done when every audit failure from step 1 has its type and element.
3. **Read the views.** For each screen the tests reach, read its view files under `App/Screens/`
   for what the audit cannot see: an image without `accessibilityLabel`, a tap gesture standing in
   for a button without `.accessibilityAddTraits(.isButton)`, a fixed `.font(.system(size:))` that
   ignores Dynamic Type, a custom control without a label, and text that is only color. Quote
   SwiftLint's `accessibility_label_for_image` and `accessibility_trait_for_button` findings
   instead of reporting them again.
   Done when each view file the tests reach was read.
4. **Report.** One line per issue: the screen, `file:line` when the view shows it, the issue type,
   and the SwiftUI fix (a label, a trait, a hint, a text style, a larger hit area). Then list the
   primary screens no audit test reaches yet (AGENTS.md Rule 24).
   Done when every issue from steps 2 and 3 appears once in the report.

An issue the team decides to accept goes through the audit's issue handler, with a comment that
names the issue and the reason (`.claude/rules/ios/testing.md`).
