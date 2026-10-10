---
paths:
  - '**/*.swift'
---

# No forced types (Swift)

When `AGENTS.md` carries a numbered rule for these, it says the same; this file is what loads while
you edit Swift.

- No `Any` or `AnyObject` as a value's type. A value whose type varies is a generic, a protocol, or
  an enum with a case per type; `any SomeProtocol` is an explicit existential and stays fine. Data
  from outside is decoded into a `Decodable` type, never read through `[String: Any]`.
- No `as!`, `try!`, force unwrap (`x!`) or implicitly unwrapped optional (`T!`): use `as?` and
  handle `nil`, `try` inside `do`/`catch` or a throwing function, and `guard let` or `if let`.
  SwiftLint reports them through `force_cast`, `force_try`, `force_unwrapping` and
  `implicitly_unwrapped_optional` where the project's config turns those rules on.
- A test unwraps with `try #require(...)`, which fails the test with a message instead of crashing
  the run.
- A suppression names one rule and gives a reason: `// swiftlint:disable:next <rule> - <reason>`.
