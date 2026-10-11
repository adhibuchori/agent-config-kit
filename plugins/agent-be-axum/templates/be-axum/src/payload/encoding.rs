//! Bytes on the wire: every binary field of an envelope (nonce, ciphertext, a public key) travels
//! inside JSON or a header as unpadded base64url, the characters a URL, a header parser or a log
//! pipeline leaves alone. Reading is lenient the way the other implementations are: standard
//! base64 as a person pastes it, with or without padding, around whitespace.

use base64::Engine as _;
use base64::alphabet::URL_SAFE;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::engine::{DecodePaddingMode, GeneralPurpose, GeneralPurposeConfig};

/// The lenient reader: url-safe alphabet (the standard one is mapped onto it first), padding
/// optional, and stray bits after the last byte ignored, as a browser's `atob` ignores them.
const LENIENT: GeneralPurpose = GeneralPurpose::new(
    &URL_SAFE,
    GeneralPurposeConfig::new()
        .with_decode_padding_mode(DecodePaddingMode::Indifferent)
        .with_decode_allow_trailing_bits(true),
);

/// Encodes bytes as unpadded base64url.
pub(crate) fn to_base64url(bytes: &[u8]) -> String {
    URL_SAFE_NO_PAD.encode(bytes)
}

/// Decodes base64url, or standard base64, back to bytes; `None` when it is neither.
pub(crate) fn from_base64url(text: &str) -> Option<Vec<u8>> {
    let mapped: String = text
        .trim()
        .chars()
        .map(|c| match c {
            '+' => '-',
            '/' => '_',
            other => other,
        })
        .collect();
    LENIENT.decode(mapped).ok()
}

#[cfg(test)]
#[path = "encoding_tests.rs"]
mod tests;
