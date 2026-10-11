//! Key agreement for public clients (a browser, an app), which can hold no secret: a bundle is
//! readable. The service keeps a long-lived P-256 key pair; the client mints an ephemeral one and
//! sends its public half in `x-payload-epk` on every request, and both sides derive the same
//! AES-256-GCM key (ECDH, then HKDF-SHA-256 with an empty salt and the label below). The service
//! re-derives it per request and stores nothing. This buys integrity and resistance to passive
//! capture, not confidentiality from the person running the client: see the contract's threat
//! model before describing it to anyone.

use std::fmt;

use p256::elliptic_curve::ecdh::{SharedSecret, diffie_hellman};
use p256::elliptic_curve::sec1::ToSec1Point as _;
use p256::{NistP256, PublicKey, SecretKey};
use serde::Deserialize;
use sha2::Sha256;

use super::cipher::{AesKey, KEY_BYTES};
use super::code::{PayloadCode, PayloadError};
use super::encoding::{from_base64url, to_base64url};

/// Domain separation, with the version in the label: a v2 schedule cannot collide with it. The
/// `/browser` label covers every public client, apps included; changing it needs envelope v2.
pub(crate) const HKDF_INFO: &[u8] = b"payload-envelope/v1/browser";

/// The `kid` of an envelope sealed under an agreed key; never a pre-shared key's id.
pub(crate) const ECDH_KID: &str = "ecdh";

/// An uncompressed SEC1 point: `0x04 || X || Y`.
const POINT_BYTES: usize = 65;

/// `PAYLOAD_SERVER_JWK` decoded: a P-256 private JWK with exactly these members.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Jwk {
    kty: String,
    crv: String,
    d: String,
    x: String,
    y: String,
}

/// The service's long-lived key pair. Its `Debug` prints only the public half.
pub(crate) struct ServerKey {
    secret: SecretKey,
    public: [u8; POINT_BYTES],
}

impl fmt::Debug for ServerKey {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "ServerKey({})", self.public_key())
    }
}

impl ServerKey {
    /// Reads base64url JWK text, the format `scripts/generate/payload-server-key.mjs` writes. The
    /// public half must be the one `d` derives, so the two can never drift apart.
    pub(crate) fn from_jwk_text(text: &str) -> Option<Self> {
        let jwk: Jwk = serde_json::from_slice(&from_base64url(text)?).ok()?;
        if jwk.kty != "EC" || jwk.crv != "P-256" {
            return None;
        }
        let secret = SecretKey::from_slice(&field(&jwk.d)?).ok()?;
        let derived = secret.public_key().to_sec1_point(false);
        let mut claimed = vec![0x04];
        claimed.extend(field(&jwk.x)?);
        claimed.extend(field(&jwk.y)?);
        let public = <[u8; POINT_BYTES]>::try_from(derived.as_bytes()).ok()?;
        (public.as_slice() == claimed.as_slice()).then_some(Self { secret, public })
    }

    /// The public half as the handshake serves it: base64url of the uncompressed point.
    pub(crate) fn public_key(&self) -> String {
        to_base64url(&self.public)
    }

    /// The AES key agreed with the client whose public key `epk` carries.
    pub(crate) fn agree(&self, epk: &str) -> Result<AesKey, PayloadError> {
        let point = from_base64url(epk).ok_or(MALFORMED_POINT)?;
        let bytes = derive_key_bytes(&shared_secret(&self.secret, &point)?)?;
        Ok(AesKey::new(bytes))
    }
}

/// A refused peer key: not base64url, not 65 bytes from `0x04`, or not on the curve.
const MALFORMED_POINT: PayloadError = PayloadError::new(
    PayloadCode::Malformed,
    "the peer public key is not a P-256 point",
);

/// One 32-byte coordinate of the JWK.
fn field(text: &str) -> Option<Vec<u8>> {
    from_base64url(text).filter(|bytes| bytes.len() == KEY_BYTES)
}

/// The ECDH x-coordinate between `secret` and an uncompressed point. A compressed point or one
/// off the curve is refused here, which is what makes an invalid-curve attack fail.
pub(crate) fn shared_secret(
    secret: &SecretKey,
    point: &[u8],
) -> Result<SharedSecret<NistP256>, PayloadError> {
    if point.len() != POINT_BYTES || point.first() != Some(&0x04) {
        return Err(MALFORMED_POINT);
    }
    let peer = PublicKey::from_sec1_bytes(point).or(Err(MALFORMED_POINT))?;
    Ok(diffie_hellman(secret.to_nonzero_scalar(), peer.as_affine()))
}

/// The 32 key bytes HKDF-SHA-256 derives from a shared secret, with an empty salt (RFC 5869
/// §3.1: no shared random value exists) and [`HKDF_INFO`].
pub(crate) fn derive_key_bytes(
    secret: &SharedSecret<NistP256>,
) -> Result<[u8; KEY_BYTES], PayloadError> {
    let mut okm = [0; KEY_BYTES];
    // HKDF refuses only an output over 255 hash lengths; 32 bytes is one.
    let too_long = PayloadError::new(PayloadCode::Malformed, "HKDF refused the key length");
    secret
        .extract::<Sha256>(None)
        .expand(HKDF_INFO, &mut okm)
        .or(Err(too_long))?;
    Ok(okm)
}

#[cfg(test)]
#[path = "ecdh_tests.rs"]
mod tests;
