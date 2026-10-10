---
paths:
  - '**/*.rs'
---

# No casts, no `unsafe` (Rust)

When `AGENTS.md` carries a numbered rule for these, it says the same; this file is what loads while
you edit Rust.

- No `as` casts. A conversion that cannot fail uses `From`/`Into`; one that can uses `TryFrom` or
  `try_into()` and handles the error. Enforced by clippy `as_conversions` at deny.
- No `unsafe`, `transmute` included: `unsafe_code = "forbid"` in `[lints.rust]`, which no attribute
  further in can lift.
- No untyped bags: `serde_json::Value`, a map of them, or `Box<dyn Any>` appears only at a system
  boundary and is parsed into a typed struct right there, with `#[serde(deny_unknown_fields)]` where
  an unknown key is an error. No lint catches this one: the reviewer does.
- No way around the lints: a suppression is `#[expect(<lint>, reason = "...")]`, which fails once
  the lint stops firing, never `#[allow]` (clippy `allow_attributes` and
  `allow_attributes_without_reason`).
