# Paths and commands per step

| Step | Where | Command |
| --- | --- | --- |
| Copy | `Packages/AppCore/Sources/APIClient/openapi.json` (from the backend's export) | `bash scripts/check/error-codes.sh` (E2 compares the bases) |
| Regenerate | `Packages/AppCore/Sources/APIClient/GeneratedSources/` | `bash scripts/ios/api-client.sh` |
| Calls | `Packages/AppCore/Sources/APIClient/<Area>API.swift`, `Packages/AppCore/Tests/APIClientTests/<Area>APITests.swift` | `swift test --package-path Packages/AppCore --filter APIClientTests` |
| Codes | `ProblemCode` in `Packages/AppCore/Sources/APIClient/AppProblem.swift`, then each switch the compiler names | `bash scripts/check/error-codes.sh`, `bash scripts/ios/app.sh build` |
| Messages | `problem.<CODE>` in `App/Localizable.xcstrings` (`"extractionState" : "manual"`) | `node scripts/check/i18n-catalog.mjs` |
| Gates | | `bash scripts/check/gates.sh`, then `bash scripts/ios/api-client.sh --check` |

Notes for the steps:

- The spec copy and the generated folder are generated output: the `generated-guard` hook refuses
  an edit by hand, so the copy is a file copy (`cp`) from the backend's export, and the folder only
  ever changes through the script.
- The app reads the spec as JSON. A backend that exports YAML exports JSON too, or converts it before
  the copy; the error-code check reads JSON only.
- The base: `x-problem-type-base` on `Problem.type` in the spec, `AppProblem.typeBase` in the app.
  They are equal, and neither changes after a release: an installed app would show every error as
  unknown. When they differ, stop and ask which side is wrong.
- The generator emits `.undocumented` only for an operation whose spec lists no `default` response;
  map it to `AppProblem()` there.
- Map each operation's generated `Output` in an extension of it, so a test reaches every case:
  `.claude/rules/ios/packages.md` shows the shape.
- A code the backend removed leaves `ProblemCode` too, with its message key; the compiler names the
  switches that still list it.
