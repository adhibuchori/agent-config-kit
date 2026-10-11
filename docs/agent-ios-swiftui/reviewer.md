# reviewer

Agent · agent-ios-swiftui · `agent-ios-swiftui:reviewer` subagent · reads and reports only · no network

## What it does

`agent-ios-swiftui:reviewer` reviews the diff of a SwiftUI app against your `AGENTS.md` and the rules
under `.claude/rules`: views that only render, screen models with one `Phase`, the logic package and
its layers, concurrency, the generated client, error codes, tokens, tests and accessibility, and,
where the app seals bodies, the payload middleware and its error mapper. It
reports each breach with its rule number, file, line and fix, and changes no file.

It is the standards axis of a review: whether the diff does what its spec asked is a separate
reviewer's question. What swift-format, SwiftLint, the compiler or a gate already fails is left to
them.

## When to reach for it

`/agent-core:review` hands it the diff when this plugin is installed:

```text
Use the agent-ios-swiftui:reviewer subagent on the staged changes.
```

**Not for:** a repo without an `AGENTS.md`, where it stops; use
[agent-core:reviewer](../agent-core/reviewer.md) instead.

## Common questions

**Why does it look at `Text(` calls the linter passed?**
`Text(someString)` shows the string without localization, and no tool can tell a `String` from a localized key: the reviewer reads each one.

**Does it review the generated client?**
No. A hand edit to the generated client is itself the finding.

## It's working if

- Each finding cites an `AGENTS.md` rule number, file and line, with the fix.
- A clean diff gets exactly `No AGENTS.md violations found in this diff.`

## Where it fits

Called by [/agent-core:review](../agent-core/review.md), next to the
[i18n-guard](i18n-guard.md) for text and locale.
