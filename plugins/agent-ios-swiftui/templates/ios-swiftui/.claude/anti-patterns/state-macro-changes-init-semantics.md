# `@State` builds its initial value once with Xcode 27, on every view init before

**Applies to:** `@State` properties with an initial value (AGENTS.md Rules 1 and 19)
**Status:** Permanent (Xcode 27 changed `@State` into a macro)

## Symptom

The same source behaves differently on two machines, or between a laptop and CI: a screen model
that does work in its initializer runs once on one toolchain and on every parent redraw on the
other, so a request is sent several times, or a counter resets.

## Root cause

Apple's `State` documentation for Xcode 27: a `State()` property "instantiates its default value
the first time SwiftUI instantiates the view", while the property wrapper of Xcode 26 and earlier
"always instantiates its default value when SwiftUI instantiates the view" (and throws the extra
copies away). The code compiles under both.

## Fix

- Build with one Xcode everywhere: CI pins Xcode 27.0 (`macos-latest-is-a-different-xcode.md`).
- Keep the initial value of `@State` free of side effects: build the model, and start its work
  from `.task { await model.refresh() }`.

## How to catch it

The reviewer reads every `@State` initial value; a request counted in a UI test shows the repeat.

## Scope

Every `@State` with a non-trivial initial value.
