---
paths:
  - '**/*.rs'
  - 'Cargo.toml'
---

# Dead code (Rust)

Blocking in pre-commit and the Quality Gate wherever a warning fails the build
(`[build] warnings = "deny"` in `.cargo/config.toml`).

- rustc's `dead_code` reports an item nothing reaches. `unreachable_pub` (deny in `[lints.rust]`)
  reports a `pub` item no other crate can reach; make it `pub(crate)` or private, and `dead_code`
  then sees whether anything uses it.
- A finding is fixed, not silenced: delete the item rather than add `#[expect(dead_code)]`, and
  never widen it to `pub` to hide it from `dead_code`.
- Code only tests call lives in the test module (`#[cfg(test)]`). Code for one feature or target sits
  behind that `#[cfg(...)]`, so the other builds do not see it as dead.
- Never keep an item or a dependency because it "might be used later".
