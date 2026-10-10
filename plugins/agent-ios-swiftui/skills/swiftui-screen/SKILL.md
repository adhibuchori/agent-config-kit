---
name: swiftui-screen
description: Builds or changes one screen of this SwiftUI app as a tracer bullet, model first - the agreed seam, a failing test of the screen model, the model that turns it green, then the view, its catalog strings and its accessibility audit. Use when the task adds a screen, adds a state or an action to a screen, or moves logic out of a view. Not for a change to the API contract alone (use openapi-client-update) or to styling that changes no behaviour.
---

# One screen, model first

One screen at a time, end to end. Each step ends on its done line; the next starts only then. The
paths and commands for each step are in [references/steps.md](references/steps.md).

1. **Seam.** Name the screen model, its `Phase` cases, the calls the view will make on it, and the
   one boundary the tests replace (the transport, the clock, the Keychain). Show that list to the
   user and wait for agreement before the first test.
   Done when the user has agreed to the seam.
2. **Client.** When the screen needs an operation the generated client lacks, bring the client
   level with the backend's spec first (the openapi-client-update procedure), then add the
   `package` call that returns Domain values.
   Done when the package builds and the new call has its test through a canned transport.
3. **Red.** Write one test of the screen model for the first behaviour the screen must show, with
   its expected value taken from the spec or the rule, never from running the code.
   Done when that test fails for the reason the missing behaviour predicts.
4. **Green.** Write the model code that makes it pass: one `@MainActor @Observable` class whose
   display text is `LocalizedStringResource` and whose state is its `Phase`.
   Done when the test passes and nothing else changed.
5. **Next behaviour.** Repeat steps 3 and 4 for loading, empty, loaded, failed and each action, one
   test at a time.
   Done when every `Phase` case and every call has its test, and the model's file is covered in full.
6. **View.** Write the view: a switch over the phase, one branch per case, and calls to the model.
   Every word comes from the catalog, every number goes through a `FormatStyle`.
   Done when the app builds for the simulator with zero warnings.
7. **Strings.** Add each new key to the catalog with every locale the app ships, in state
   translated.
   Done when the catalog check passes.
8. **Audit.** Add or extend the screen's accessibility audit UI test, and run it.
   Done when the audit passes on the screen, or each accepted issue carries its reason.
9. **Gates.** Run the gates.
   Done when they pass, coverage included.
