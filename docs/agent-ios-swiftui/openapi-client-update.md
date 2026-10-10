# openapi-client-update

Skill · agent-ios-swiftui · `agent-ios-swiftui:openapi-client-update` · copies the spec, regenerates the client, edits the package and the catalog · no network beyond package resolution

## What it does

The `openapi-client-update` skill brings the generated API client up to date with the backend's
exported spec: it copies the spec, checks the problem-type base, regenerates the client with the
pinned generator, adds the `package` call for each new operation with its tests, makes `ProblemCode`
equal the spec's code list (every screen's switch then lists the new code), and adds each code's
message in every locale.

## When to reach for it

Claude loads it when the backend's spec changed, a screen needs a new endpoint or error code, or
the gate reports client drift or an error-code mismatch:

```text
The backend added a RATE_LIMITED error and a cancel endpoint. Update the app's client.
```

**Not for:** a change that stays inside the app; use [swiftui-screen](swiftui-screen.md) instead.

## Prerequisites

- The backend's exported `openapi.json`, with its inline `Problem.code` enum and
  `x-problem-type-base`.
- `scripts/ios/api-client.sh` and the error-code check that [/agent-ios-swiftui:setup](setup.md)
  installs, and a Mac with Xcode 27.

## Common questions

**The bases differ. What now?**
The skill stops and asks. The base never changes after a release: every installed app would show every error as unknown. One side is wrong, and only you know which.

**Why not edit the generated client directly?**
The [generated-guard](generated-guard.md) hook refuses it, and the quality gate regenerates the client and fails on any difference.

## It's working if

- `bash scripts/check/error-codes.sh` passes: the codes and the base agree with the spec, and each
  code has its message key.
- `bash scripts/ios/api-client.sh --check` reports the committed client current, and the gates pass.

## Where it fits

A procedure skill of [agent-ios-swiftui](../../plugins/agent-ios-swiftui/README.md), the app-side half of
the error-code contract the backend plugins keep.
