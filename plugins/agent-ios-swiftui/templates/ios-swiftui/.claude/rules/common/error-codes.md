---
paths:
  - 'Packages/AppCore/Sources/APIClient/**'
  - 'Packages/AppCore/Sources/Features/**'
  - 'App/Screens/**'
  - '**/*.xcstrings'
---

# Error codes: the app side of the API contract

How to follow AGENTS.md Rule 12. A code the app has no message for reaches people as a generic
"something went wrong"; this is what keeps that rare and traceable. The API side binds the
backend: every error leaves it as an RFC 9457 problem whose `type` is the API's base plus a
registered `code`, the code list is the spec's inline `Problem.code` enum, and the base is
`x-problem-type-base` on `Problem.type`.

## How the app reads a problem

The generated client decodes every `Problem` into `AppProblem` (`typeOverrides`), which reads each
member on its own, so a code added after this build shipped still decodes. `knownCode` resolves it:

1. A `type` that is not a string is ignored: it counts as `about:blank`.
2. `type` equal to `AppProblem.typeBase` plus a code in `ProblemCode`: that code.
3. `type` absent or `about:blank`: the code alone (an API that does not mint types yet).
4. Anything else, a known code under another base or a `type` whose tail is not the code:
   unknown, so `nil`.
5. `detail` is never read, and nothing branches on the HTTP status.

## What a screen does

- Switch over `problem.knownCode` with every `ProblemCode` case and `nil`, and no `default:`
  (SwiftLint `no_default_on_problem_code`): a code added to `ProblemCode` then fails the build until
  every screen maps it.
- Show the catalog message `problem.<CODE>` (`problem.messageKey`); for an unknown problem show
  `problem.unknown` and the reference `CODE · <request id prefix>` (`problem.reference`) a person
  can quote to support.
- Branch on the code, never on `status`: "any 409 means a duplicate" reports a refused request as
  something else.

## When the spec changes

Copy the backend's new `openapi.json` into `Packages/AppCore/Sources/APIClient/`, run
`bash scripts/ios/api-client.sh`, then make `scripts/check/error-codes.sh` pass:

- E1: `ProblemCode` lists exactly the spec's codes. Add the case, then fix every switch the
  compiler names.
- E2: `AppProblem.typeBase` equals the spec's `x-problem-type-base`. The base never changes after
  a release: every installed app would show every error as unknown.
- E3: each code, and `unknown`, has the manual key `problem.<CODE>` in the app's String Catalog,
  translated in every locale.
