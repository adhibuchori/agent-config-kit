//! The one cipher on the wire: AES-256-GCM with a 96-bit nonce and the 128-bit tag appended. The
//! AAD is never sent; it is mixed into the tag, so a ciphertext lifted from one route and replayed
//! on another fails to open instead of decrypting into a plausible body.

use std::fmt;

use aes_gcm::aead::{Aead as _, Generate as _, KeyInit as _, Payload};
use aes_gcm::{Aes256Gcm, Nonce};

use super::code::{PayloadCode, PayloadError};

/// The nonce length GCM is specified for; any other length takes another derivation path.
pub(crate) const IV_BYTES: usize = 12;

/// AES-256: 32 bytes of key material.
pub(crate) const KEY_BYTES: usize = 32;

/// The one refusal for a wrong key, a tampered body and a foreign AAD alike: saying which one
/// failed tells a prober which half of the guess was right.
const REJECTED: PayloadError =
    PayloadError::new(PayloadCode::Rejected, "the payload did not authenticate");

/// An AES-256-GCM key. Its `Debug` never prints the key.
#[derive(Clone)]
pub(crate) struct AesKey(Aes256Gcm);

impl AesKey {
    /// A key from its 32 bytes.
    pub(crate) fn new(bytes: [u8; KEY_BYTES]) -> Self {
        Self(Aes256Gcm::new(&bytes.into()))
    }
}

impl fmt::Debug for AesKey {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("AesKey(..)")
    }
}

/// Encrypts `plaintext` bound to `aad` under a fresh nonce; returns the nonce and the ciphertext
/// with its tag. One nonce per encryption, never reused under a key: reuse breaks GCM outright.
pub(crate) fn seal(
    key: &AesKey,
    plaintext: &[u8],
    aad: &[u8],
) -> Result<([u8; IV_BYTES], Vec<u8>), PayloadError> {
    let nonce = Nonce::generate();
    let too_long = PayloadError::new(PayloadCode::Malformed, "the body is too long to seal");
    let sealed = key
        .0
        .encrypt(
            &nonce,
            Payload {
                msg: plaintext,
                aad,
            },
        )
        .or(Err(too_long))?;
    Ok((nonce.into(), sealed))
}

/// Verifies and decrypts; any failure, a nonce of the wrong length included, is `ENVELOPE_REJECTED`.
pub(crate) fn open(
    key: &AesKey,
    iv: &[u8],
    sealed: &[u8],
    aad: &[u8],
) -> Result<Vec<u8>, PayloadError> {
    let nonce = Nonce::try_from(iv).or(Err(REJECTED))?;
    key.0
        .decrypt(&nonce, Payload { msg: sealed, aad })
        .or(Err(REJECTED))
}

#[cfg(test)]
#[path = "cipher_tests.rs"]
mod tests;
