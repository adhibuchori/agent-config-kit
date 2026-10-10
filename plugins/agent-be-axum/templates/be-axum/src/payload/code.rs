//! The closed set of ways an envelope can fail to become a payload (Rule 34). Codes, not text,
//! because they cross the wire: a client maps each to a message, and the internal reason goes to
//! the log. `PayloadCode` never derives `Deserialize` and no array lists its variants, so a code
//! nothing raises fails the build through `dead_code`, as `ErrorCode` does.

use crate::platform::error::WireCode;

/// Every payload failure the boundary reports.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum PayloadCode {
    /// A sealed route received plaintext, or a body that is not an envelope of a known version.
    Required,
    /// Opened plaintext that is not JSON, a peer key that is not a P-256 point, or (as a 500) an
    /// answer this side cannot seal because it is not JSON.
    Malformed,
    /// Outside the freshness window: a replay, or two clocks that drifted apart.
    Expired,
    /// A `kid` this side does not hold, or an agreed key this service cannot agree.
    KeyUnknown,
    /// The tag did not verify: tampering, the wrong key, or another route, method or status.
    Rejected,
}

impl WireCode for PayloadCode {
    fn as_str(self) -> &'static str {
        match self {
            Self::Required => "ENVELOPE_REQUIRED",
            Self::Malformed => "ENVELOPE_MALFORMED",
            Self::Expired => "ENVELOPE_EXPIRED",
            Self::KeyUnknown => "ENVELOPE_KEY_UNKNOWN",
            Self::Rejected => "ENVELOPE_REJECTED",
        }
    }

    fn title(self) -> &'static str {
        match self {
            Self::Required => "Sealed body required",
            Self::Malformed => "Malformed envelope",
            Self::Expired => "Envelope expired",
            Self::KeyUnknown => "Unknown payload key",
            Self::Rejected => "Envelope rejected",
        }
    }
}

/// The codes as the document lists them, after `ErrorCode`'s. A test holds this list equal to
/// the codes above, one for one.
pub(crate) const WIRE_NAMES: [&str; 5] = [
    "ENVELOPE_REQUIRED",
    "ENVELOPE_MALFORMED",
    "ENVELOPE_EXPIRED",
    "ENVELOPE_KEY_UNKNOWN",
    "ENVELOPE_REJECTED",
];

/// A payload failure: the code for the wire, and a fixed reason for the log that never holds a
/// key, a body or anything a client sent.
#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
#[error("{reason}")]
pub(crate) struct PayloadError {
    pub(crate) code: PayloadCode,
    pub(crate) reason: &'static str,
}

impl PayloadError {
    pub(crate) const fn new(code: PayloadCode, reason: &'static str) -> Self {
        Self { code, reason }
    }
}

#[cfg(test)]
#[path = "code_tests.rs"]
mod tests;
