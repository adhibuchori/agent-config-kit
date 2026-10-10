//! The wire format: what an envelope is, and what its ciphertext is bound to. Every constant here
//! has a twin in each other implementation of the contract, and the shared test vectors
//! (`scripts/check/payload-vectors.json`) compare them: two envelopes that drifted apart are two
//! services that fail to talk with an error that says nothing about why.

use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

use super::code::{PayloadCode, PayloadError};

/// The media type of a sealed body: not `application/json`, so a proxy, a log filter or a layer
/// tells an envelope from plaintext without parsing it.
pub(crate) const SEALED_MEDIA_TYPE: &str = "application/vnd.payload-envelope+json";

/// Bumped only for a breaking change. An unknown version is refused, never guessed at.
pub(crate) const ENVELOPE_VERSION: u32 = 1;

/// The one algorithm version 1 defines.
pub(crate) const ENVELOPE_ALG: &str = "A256GCM";

/// A public client's ephemeral P-256 key, on every request with or without a body.
pub(crate) const EPK_HEADER: &str = "x-payload-epk";

/// A server caller's pre-shared key id, so a bodiless request is answered under that key.
pub(crate) const KID_HEADER: &str = "x-payload-kid";

/// How far apart two clocks may be, either way, in milliseconds. Not replay protection on its
/// own: that needs a nonce store.
pub(crate) const MAX_CLOCK_SKEW_MS: u64 = 120_000;

/// A sealed body as it travels. The field order is the order the other implementations write.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Envelope {
    /// Format version; [`ENVELOPE_VERSION`].
    pub(crate) v: u32,
    /// [`ENVELOPE_ALG`].
    pub(crate) alg: String,
    /// Which key sealed it: a pre-shared key's id, or `ecdh` for an agreed key.
    pub(crate) kid: String,
    /// Base64url 96-bit nonce, fresh for every encryption.
    pub(crate) iv: String,
    /// Base64url ciphertext with the 16-byte tag appended.
    pub(crate) ct: String,
    /// Epoch milliseconds when it was sealed; an integer, never a float.
    pub(crate) ts: i64,
}

/// Reads an envelope of a version this build knows out of a raw body, or refuses it as plaintext.
pub(crate) fn parse(raw: &[u8]) -> Result<Envelope, PayloadError> {
    let refused = PayloadError::new(PayloadCode::Required, "the body is not a payload envelope");
    let envelope: Envelope = serde_json::from_slice(raw).or(Err(refused))?;
    if envelope.v != ENVELOPE_VERSION || envelope.alg != ENVELOPE_ALG {
        return Err(refused);
    }
    Ok(envelope)
}

/// Whether `ts` sits inside the window around `now`. A future timestamp is refused too:
/// accepting it would let an envelope be post-dated for as long as anyone liked.
pub(crate) const fn is_fresh(ts: i64, now: i64) -> bool {
    now.abs_diff(ts) <= MAX_CLOCK_SKEW_MS
}

/// The current time in epoch milliseconds, the unit `ts` is in.
pub(crate) fn now_millis() -> i64 {
    let since = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    i64::try_from(since.as_millis()).unwrap_or(i64::MAX)
}

/// The AAD binding a request envelope to its method and registry pattern (`/api/items/:id`, not
/// the URL, so both sides agree without sharing a URL normaliser).
pub(crate) fn request_aad(method: &str, pattern: &str, kid: &str, ts: i64) -> Vec<u8> {
    let method = method.to_ascii_uppercase();
    format!("{ENVELOPE_VERSION}.{method}.{pattern}.{kid}.{ts}").into_bytes()
}

/// The AAD binding a response envelope to its status, so a 200 body never opens as a 403's.
pub(crate) fn response_aad(status: u16, pattern: &str, kid: &str, ts: i64) -> Vec<u8> {
    format!("{ENVELOPE_VERSION}.{status}.{pattern}.{kid}.{ts}").into_bytes()
}

/// What one envelope is bound to, before its key id and timestamp are known.
#[derive(Debug, Clone, Copy)]
pub(crate) enum Binding<'a> {
    /// A request body: its method and registry pattern.
    Request { method: &'a str, pattern: &'a str },
    /// A response body: its status and registry pattern.
    Response { status: u16, pattern: &'a str },
}

impl Binding<'_> {
    /// The AAD for this binding, key id and timestamp.
    pub(crate) fn aad(self, kid: &str, ts: i64) -> Vec<u8> {
        match self {
            Self::Request { method, pattern } => request_aad(method, pattern, kid, ts),
            Self::Response { status, pattern } => response_aad(status, pattern, kid, ts),
        }
    }
}

#[cfg(test)]
#[path = "envelope_tests.rs"]
mod tests;
