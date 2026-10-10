//! A JSON body into an envelope and back: the one place that decides the order of operations.
//! Freshness goes first, so a replayed envelope costs a subtraction, not a GCM pass.

use serde::de::IgnoredAny;

use super::cipher::{self, AesKey};
use super::code::{PayloadCode, PayloadError};
use super::encoding::{from_base64url, to_base64url};
use super::envelope::{Binding, ENVELOPE_ALG, ENVELOPE_VERSION, Envelope, is_fresh};

/// Seals JSON bytes for `kid`, stamped `now`. A body that is not JSON is refused: the other side
/// parses what it opens, and a body it cannot parse is one this side should not have sent.
pub(crate) fn seal_json(
    key: &AesKey,
    kid: &str,
    body: &[u8],
    binding: Binding<'_>,
    now: i64,
) -> Result<Envelope, PayloadError> {
    if !is_json(body) {
        return Err(PayloadError::new(
            PayloadCode::Malformed,
            "the body to seal is not JSON",
        ));
    }
    let (iv, ct) = cipher::seal(key, body, &binding.aad(kid, now))?;
    Ok(Envelope {
        v: ENVELOPE_VERSION,
        alg: ENVELOPE_ALG.to_owned(),
        kid: kid.to_owned(),
        iv: to_base64url(&iv),
        ct: to_base64url(&ct),
        ts: now,
    })
}

/// Checks freshness, verifies, decrypts, and returns the plaintext once it is known to be JSON.
/// The caller that knows the route validates its shape (`ValidJson`).
pub(crate) fn open_json(
    key: &AesKey,
    envelope: &Envelope,
    binding: Binding<'_>,
    now: i64,
) -> Result<Vec<u8>, PayloadError> {
    if !is_fresh(envelope.ts, now) {
        return Err(PayloadError::new(
            PayloadCode::Expired,
            "the envelope is outside the window",
        ));
    }
    let rejected = PayloadError::new(PayloadCode::Rejected, "an envelope field is not base64url");
    let iv = from_base64url(&envelope.iv).ok_or(rejected)?;
    let ct = from_base64url(&envelope.ct).ok_or(rejected)?;
    let plaintext = cipher::open(key, &iv, &ct, &binding.aad(&envelope.kid, envelope.ts))?;
    if !is_json(&plaintext) {
        return Err(PayloadError::new(
            PayloadCode::Malformed,
            "the opened payload is not JSON",
        ));
    }
    Ok(plaintext)
}

/// Whether the bytes are one JSON value.
fn is_json(bytes: &[u8]) -> bool {
    serde_json::from_slice::<IgnoredAny>(bytes).is_ok()
}

#[cfg(test)]
#[path = "codec_tests.rs"]
mod tests;
