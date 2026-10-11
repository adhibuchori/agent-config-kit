# `#![allow(...)]` passes clippy's `allow_attributes` and never goes stale

**Applies to:** clippy 1.99 with `allow_attributes` and `allow_attributes_without_reason` denied
**Status:** A standing trap; `rust-source.mjs` ALLOW refuses `#![allow(` anywhere

## Symptom

A module starts with `#![allow(clippy::unwrap_used, reason = "experiment")]`, the build is green,
and the module unwraps freely for months. Nothing reports the allow when its reason is gone.

## Root Cause

`allow_attributes` checks outer attributes only (`if let AttrStyle::Outer = attr.style` in
clippy's `allow_attributes.rs`), and an `allow` is never reported as unfulfilled, unlike `expect`.
Reproduced with both lints at `deny`.

## Fix

`#[expect(lint, reason = "...")]` on the one item that needs it: it fails the build through
`unfulfilled_lint_expectations` once the lint stops firing.

## When to revisit

If clippy starts checking inner attributes, the ALLOW check becomes a second line of defence.
