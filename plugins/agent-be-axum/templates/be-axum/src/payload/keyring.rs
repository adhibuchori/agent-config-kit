//! Pre-shared keys for server callers, which never reach a client a person runs. One variable
//! holds `kid:base64key`, because a key and the id naming it are one fact: split across two
//! variables, one gets rotated without the other. Rotation adds `<NAME>_NEXT`: deploy both sides
//! with it, then swap, and no request falls into the gap (Rule 32). Pure: it parses what
//! `platform::config` read and never reads the environment itself.

use super::cipher::{AesKey, KEY_BYTES};
use super::code::{PayloadCode, PayloadError};
use super::ecdh::ECDH_KID;
use super::encoding::from_base64url;
use super::setup::PayloadSetupError;

/// The longest key id: short, printable, public.
const MAX_KID: usize = 32;

/// The keys this service seals with and accepts; the first configured one seals.
#[derive(Debug)]
pub(crate) struct KeyRing {
    entries: Vec<(String, AesKey)>,
}

impl KeyRing {
    /// A ring from `(variable, value)` pairs in priority order; unset and blank values are
    /// skipped, so a rotation slot needs no branch. `None` when no key is configured.
    pub(crate) fn from_sources(
        sources: &[(&'static str, Option<&str>)],
    ) -> Result<Option<Self>, PayloadSetupError> {
        let mut entries: Vec<(String, AesKey)> = Vec::new();
        for &(name, value) in sources {
            let Some(value) = value.map(str::trim).filter(|value| !value.is_empty()) else {
                continue;
            };
            let (kid, key) = entry(value).ok_or(PayloadSetupError::Key(name))?;
            if entries.iter().any(|(known, _)| *known == kid) {
                return Err(PayloadSetupError::DuplicateKid(name));
            }
            entries.push((kid, key));
        }
        Ok((!entries.is_empty()).then_some(Self { entries }))
    }

    /// The id the primary key seals under.
    pub(crate) fn primary_kid(&self) -> &str {
        self.entries.first().map_or("", |(kid, _)| kid.as_str())
    }

    /// The key an envelope's or a caller's `kid` names.
    pub(crate) fn resolve(&self, kid: &str) -> Result<&AesKey, PayloadError> {
        let unknown = PayloadError::new(PayloadCode::KeyUnknown, "no payload key has this kid");
        let found = self.entries.iter().find(|(known, _)| known == kid);
        found.map(|(_, key)| key).ok_or(unknown)
    }
}

/// One `kid:base64key` value, or `None` when it is malformed.
fn entry(value: &str) -> Option<(String, AesKey)> {
    let (kid, material) = value.split_once(':')?;
    let kid = kid.trim();
    let valid_kid = (1..=MAX_KID).contains(&kid.len())
        && kid
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'-'))
        && kid != ECDH_KID;
    let bytes = <[u8; KEY_BYTES]>::try_from(from_base64url(material)?).ok()?;
    valid_kid.then(|| (kid.to_owned(), AesKey::new(bytes)))
}

#[cfg(test)]
#[path = "keyring_tests.rs"]
mod tests;
