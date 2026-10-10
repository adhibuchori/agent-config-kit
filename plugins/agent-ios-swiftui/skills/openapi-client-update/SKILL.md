---
name: openapi-client-update
description: Brings this iOS app's generated API client up to date with the backend's exported OpenAPI spec - copy the spec, regenerate with the pinned generator, add the package call for each new operation, map every new error code with every screen's switch listing it, and add its message in every locale. Use when the backend's spec changed, a new endpoint or error code is needed, or the gate reports client drift or an error-code mismatch. Not for a change inside the app alone.
---

# API client update

One spec change at a time. Each step ends on its done line; the next starts only then. The paths
and commands for each step are in [references/steps.md](references/steps.md).

1. **Copy.** Copy the backend's exported spec over the app's copy, byte for byte, and compare the
   problem-type base it publishes with the one the app holds.
   Done when the diff of the copy shows only what the backend changed, and the two bases agree.
2. **Regenerate.** Run the generator through the repo's script.
   Done when the generated folder changed only where the spec did, and the package builds.
3. **Calls.** For each new operation a screen needs, add one `package` call that returns Domain
   values or throws an `AppProblem`, with a test through a canned transport for each response the
   spec lists.
   Done when every new call is covered in full.
4. **Codes.** Make the app's code list equal the spec's: add each new code as a case, then fix every
   switch the compiler names, case by case, with no default.
   Done when the error-code check and the build both pass.
5. **Messages.** Add the manual key of each new code to the app's catalog, translated in every locale
   the app ships, with wording that tells the person what to do next.
   Done when the catalog check and the error-code check pass.
6. **Gates.** Run the gates.
   Done when they pass, and the client drift check reports the committed client current.
