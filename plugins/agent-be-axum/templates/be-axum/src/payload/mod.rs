//! The payload contract's core (`.claude/PAYLOAD-CONTRACT.md`, Rules 30 to 34): envelopes, the
//! cipher, key agreement, the key ring, the switch and the endpoint registry. No HTTP type enters
//! this folder; `src/routes/payload.rs` is the glue, and only `src/routes/` and `src/lib.rs` name
//! `crate::payload` (Rule 31).
//!
//! Setup installs this folder unwired, and cargo compiles no module nothing declares, so the
//! skeleton stays green until you wire it in by hand:
//!
//! 1. `cargo add p256@0.14.0 --no-default-features --features ecdh`, then
//!    `cargo add aes-gcm@0.11.1 sha2@0.11.0 base64@0.22.1`.
//! 2. `src/platform/config.rs`: four `Option<String>` fields on `Config`, `payload_mode`,
//!    `payload_key`, `payload_key_next` and `payload_server_jwk`, read from `PAYLOAD_MODE`,
//!    `PAYLOAD_KEY`, `PAYLOAD_KEY_NEXT` and `PAYLOAD_SERVER_JWK` (Rule 19).
//! 3. `src/routes/paths.rs`: `pub(crate) const PAYLOAD_HANDSHAKE: &str = "/api/payload/handshake";`.
//! 4. `src/routes/mod.rs`: `pub(crate) mod payload;`, `.merge(payload::routes())` in `router()`,
//!    then `payload::document(router.get_openapi_mut())` on the merged router, which lists the
//!    `ENVELOPE_*` codes in the spec's `Problem.code`.
//! 5. `src/lib.rs`: `mod payload;`, `pub use payload::PayloadSetupError;`,
//!    `pub use routes::payload::check_payload_settings;`, and in `app()`, after `split_for_parts`:
//!    `let router = routes::payload::seal(router, &config);` (a `route_layer`, so every route
//!    must be merged before it). `src/main.rs`: `check_payload_settings(&config)?;` beside
//!    `check_problem_type_base`.
//! 6. `node scripts/generate/payload-registry.mjs` writes `endpoints_generated.rs` from the spec
//!    and `payload.config.json`; `cargo run --locked --quiet --bin openapi` refreshes the spec.
//! 7. Keys, on your own machine: `node scripts/generate/payload-server-key.mjs | bash
//!    scripts/env/set.sh .env.development PAYLOAD_SERVER_JWK` for public clients, and
//!    `PAYLOAD_KEY=kid:base64key` on both sides of a server-to-server hop.
//!
//! The gate `node scripts/check/payload-registry.mjs` stays red until the spec lists the five
//! `ENVELOPE_*` codes and the handshake: a contract adopted halfway never passes quietly.

mod boundary;
mod cipher;
mod code;
mod codec;
mod ecdh;
mod encoding;
mod endpoints_generated;
mod envelope;
mod keyring;
mod mode;
mod policy;
mod setup;

pub(crate) use boundary::{Boundary, Exchange, Route};
pub(crate) use code::{PayloadCode, PayloadError, WIRE_NAMES};
pub(crate) use endpoints_generated::{CONFIG_MODE, ENDPOINTS};
pub(crate) use envelope::{EPK_HEADER, KID_HEADER, SEALED_MEDIA_TYPE, now_millis};
pub(crate) use mode::Mode;
pub use setup::PayloadSetupError;
pub(crate) use setup::Settings;

#[cfg(test)]
pub(crate) use policy::{Endpoint, Policy};

#[cfg(test)]
#[path = "vectors_tests.rs"]
mod vectors_tests;
