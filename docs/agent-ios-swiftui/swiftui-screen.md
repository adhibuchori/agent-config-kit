# swiftui-screen

Skill · agent-ios-swiftui · `agent-ios-swiftui:swiftui-screen` · edits the app and its package, runs tests and the build · no network

## What it does

The `swiftui-screen` skill builds or changes one screen as a tracer bullet, model first: it agrees
the seam with you, writes a failing test of the screen model, the model that turns it green (one
`Phase`, localized text), then the view, its catalog strings in every locale and its accessibility
audit test, and ends on the gates.

## When to reach for it

Claude loads it when a task adds a screen, adds a state or an action to one, or moves logic out of
a view:

```text
Add an order detail screen that shows the order and lets me cancel it.
```

**Not for:** a change to the API contract alone; use [openapi-client-update](openapi-client-update.md)
instead, which this skill calls when the screen needs a new operation.

## Prerequisites

- The files [/agent-ios-swiftui:setup](setup.md) installs: the rules, `scripts/ios/app.sh` and the
  gates.
- A Mac with Xcode 27 for the build and the audit step.

## Common questions

**Why does it stop before the first test?**
It names the screen model, its phases, its calls and the one boundary the tests replace, and waits for your agreement. Changing the seam after the tests exist costs more than agreeing on it first.

**Does it test the view?**
The view holds no logic to test; its audit test covers what a person meets. Logic goes in the screen model, which is covered file by file.

## It's working if

- Each step ends on its "Done when" line, and the model's tests went red before green.
- The gates pass at the end, the new strings are in every locale, and the screen has its audit test.

## Where it fits

A procedure skill of [agent-ios-swiftui](../../plugins/agent-ios-swiftui/README.md), reviewed afterwards
by the [reviewer](reviewer.md) and the [i18n-guard](i18n-guard.md).
