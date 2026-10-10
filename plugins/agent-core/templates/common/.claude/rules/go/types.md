---
paths:
  - '**/*.go'
---

# Checked types (Go)

When `AGENTS.md` carries a numbered type rule, it says the same; this file is what loads while you
edit Go.

- A type assertion takes the two-value form, `v, ok := x.(T)`, and handles `!ok`; the one-value
  form panics on a wrong type. golangci-lint's errcheck with `check-type-assertions: true` reports
  it. A type switch is the other safe form.
- Code that works on several types is generic (`[T any]`, or a narrower constraint), not `any` plus
  a type switch that lists the cases. `any` stays where a value's type truly varies, such as a
  decoder's target or a log attribute, and is spelled `any`, not `interface{}`.
- Data from outside (a request body, a config file, a queue message) is decoded into a struct,
  with `DisallowUnknownFields` where an unknown key is an error, never walked as `map[string]any`.
- No `unsafe`, and no `reflect` to get around a type: where the project has a depguard rule for
  `unsafe`, it refuses the import.
- A suppression names its linter and gives a reason: `//nolint:errcheck // <reason>`.
