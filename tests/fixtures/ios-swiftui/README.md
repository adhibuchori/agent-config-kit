# ios-swiftui fixtures

Inputs for `tests/agent-ios-swiftui/`. Each test copies what it needs into its own temp repo; the
plugin's own seeds (`AppProblem.swift`, `Config/*.xcconfig`, the privacy manifest) are copied from
the template at run time, so they are never duplicated here.

| Path | What it is |
| --- | --- |
| `app/` | A probe app: an Xcode project with buildable folders whose configurations are based on `Config/*.xcconfig`, a String Catalog in two locales with the `problem.*` keys, and a backend spec copy whose codes and base match the seeded `AppProblem` |
| `catalogs/defects.xcstrings` | One key per catalog defect: a missing locale (I1), units in state new and needs_review and a plural leaf in state new (I2), a stale key (I3), a manual key (I5), and a key marked not to translate |
| `packages/clean.json` | `swift package dump-package` output of a clean `Packages/AppCore`, served to `scripts/check/package-graph.sh` by a stub `swift`; each breach probe changes one thing in a copy |
