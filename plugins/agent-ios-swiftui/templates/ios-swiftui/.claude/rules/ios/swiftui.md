---
paths:
  - 'App/**/*.swift'
  - 'App/**/*.xcprivacy'
  - 'Config/*.xcconfig'
  - '*.xcodeproj/project.pbxproj'
---

# The app target: composition root and views

How to follow AGENTS.md Rules 1, 3, 4, 14, 20, 25 and 28 in the app target. The rules themselves
are stated once, in AGENTS.md.

## Composition root (Rule 1)

`App/<App>App.swift` builds the API, the screen models and their dependencies, and hands them to
the views. It is the one place that knows the server URL and the transport. A screen model is held
where it is created, in `@State private var`, and passed down as a plain `let`:

```swift
@main
struct OrdersApp: App {
    @State private var orders = OrderListModel(load: OrdersAPI(serverURL: server).orders)
    var body: some Scene { WindowGroup { OrderListView(model: orders) } }
}
```

With Xcode 27, `@State` is a macro that builds its initial value once, where the Xcode 26 property
wrapper built it on every view init (`.claude/anti-patterns/state-macro-changes-init-semantics.md`):
keep the initial value free of side effects either way.

## A view renders its model (Rules 3 and 4)

- One screen, one `@Observable` model in `Packages/AppCore/Sources/Features/`, exposing one `Phase`
  enum. The view switches over it, one branch per case:

  ```swift
  switch model.phase {
  case .loading: ProgressView("orders.loading")
  case .empty: ContentUnavailableView("orders.empty", systemImage: "tray")
  case .loaded(let orders): List(orders) { Text($0.total, format: .currency(code: "USD")) }
  case .failed(let problem): ProblemView(problem: problem)
  }
  ```

- A `.task { await model.refresh() }` or a button action calls the model; the body of that
  `Task` is one call, never a decision.
- What changes the screen's data (filtering, sorting, the current time, a request, a stored value)
  is a function of the model, where `swift test` reaches it.
- A loading placeholder is the real view with `.redacted(reason: .placeholder)`, so it keeps the
  real layout.

## What the app does not decide (Rule 14)

Hide or disable a control for the user's convenience, never for safety: the server refuses what
the user may not do, and the screen shows that refusal through its problem text.

## Build settings (Rules 19, 20 and 28)

- A setting goes in `Config/Base.xcconfig` (every target), or in a target's own xcconfig named as
  that target's base configuration. The project file keeps target identity only;
  `scripts/check/xcode-settings.sh` fails a `SWIFT_*` key in `project.pbxproj`.
- `SWIFT_PACKAGE_NAME = appcore` lets the app call the logic package's `package` API: nothing has
  to become `public` for the app to use it.
- An API key or other secret never goes in an xcconfig, the app's property list or the bundle:
  every byte ships to every device. Secrets come from the server, after sign-in.
- Requests use HTTPS; App Transport Security stays on, so no `NSAllowsArbitraryLoads`.

## Privacy manifest (Rule 25)

`App/PrivacyInfo.xcprivacy` declares each required-reason API category the code uses
(`UserDefaults` and `@AppStorage`, file timestamps, system boot time, disk space, active
keyboards) with a reason code from Apple's list for that category, such as `CA92.1` for user
defaults only this app reads:

```xml
<dict>
	<key>NSPrivacyAccessedAPIType</key>
	<string>NSPrivacyAccessedAPICategoryUserDefaults</string>
	<key>NSPrivacyAccessedAPITypeReasons</key>
	<array><string>CA92.1</string></array>
</dict>
```

`scripts/check/privacy-manifest.sh` names the file and line of each use it finds.
