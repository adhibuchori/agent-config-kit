---
paths:
  - 'Packages/**/*.swift'
  - 'Packages/**/Package.resolved'
  - 'scripts/check/package-graph.json'
---

# The logic package: Domain, APIClient, Features

How to follow AGENTS.md Rules 1, 2, 10, 11, 13, 21 and 26 in `Packages/AppCore`. The rules
themselves are stated once, in AGENTS.md.

## Targets and what each imports (Rules 1 and 2)

| Target | Holds | Imports |
| --- | --- | --- |
| `Domain` | values and rules of the product, such as `Order` | Foundation |
| `APIClient` | the generated client (internal), `AppProblem`, one `package` call per operation | Domain, OpenAPIRuntime, OpenAPIURLSession |
| `Features` | one `@MainActor @Observable` screen model per screen | Domain, APIClient, Observation |

- A new target arrives with its first source file and its test target `<Target>Tests`, and gets
  its row under `layers` in `scripts/check/package-graph.json`; `package-graph.sh` fails a target
  that has neither. Split `Features` by area (`OrdersFeature`) only when it grows, and an area never
  imports another.
- Share between targets with `package` access; the app reads it too (`SWIFT_PACKAGE_NAME` in
  `Config/Base.xcconfig`). `public` is for a library other packages use.
- A file is named after its main type, and its test file mirrors it:
  `Sources/Features/OrderListModel.swift` → `Tests/FeaturesTests/OrderListModelTests.swift`.
- The package's code is `nonisolated` by default, so network and decoding stay off the main
  actor; a screen model says `@MainActor` itself.

## The API client (Rules 10 and 11)

- `Sources/APIClient/openapi.json` is the backend's exported spec, copied as is;
  `openapi-generator-config.yaml` beside it keeps the client `internal` and decodes every problem
  into `AppProblem`. `bash scripts/ios/api-client.sh` regenerates `GeneratedSources/` there; commit
  both. The quality gate regenerates and fails on a difference. `swift build` notes the two files
  as unhandled: the generator reads them from the target folder, and Xcode counts no warning.
- Each operation the screens use gets one `package` function in `APIClient` that returns Domain
  values or throws an `AppProblem`. Map the generated `Output` in an extension, so a test can reach
  every case:

  ```swift
  extension Operations.ListOrders.Output {
      func orders() throws -> [Order] {
          switch self {
          case .ok(let response): return try response.body.json.map(Order.init)
          case .default(_, let response): throw try response.body.applicationProblemJson
          }
      }
  }
  ```

  An operation whose spec declares no `default` response also has `.undocumented`: throw
  `AppProblem()` there.
- Tests replace the transport, the system boundary, with a canned `ClientTransport`, so the
  generated decoding runs for real. Nothing else in the app is replaced.
- `URLSession` appears only as the client's `URLSessionTransport`; a route path appears only in
  the generated code.

## Tokens (Rule 13)

The refresh token is a Keychain item (`kSecClassGenericPassword`,
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) behind a protocol, with an in-memory fake for
the logic tests. The bearer token lives in memory, in an actor, and is minted again from the
refresh token. Sign-in goes through `ASWebAuthenticationSession` or passkeys.

## Packages and pins (Rule 21)

- A remote package: `.package(url:, exact: "x.y.z")`, then commit both `Packages/AppCore/
  Package.resolved` and the app project's `project.xcworkspace/xcshareddata/swiftpm/
  Package.resolved` (Xcode resolves into the second); `package-graph.sh` fails when they disagree.
- Raise one package family per change, after reading its release notes.
- A build-tool plugin or a macro runs third-party code in every build: record the decision, and
  name it under `plugins` in `scripts/check/package-graph.json`.

## Logs (Rule 26)

`Logger(subsystem:category:)` from `os`, one per area. Interpolate values with their privacy
(`\(id, privacy: .public)`); a token, an email or a request body stays `.private`.
