//! The boundary: everything the HTTP glue (`src/routes/payload.rs`) asks of the contract, with
//! no HTTP type in it. Built once at startup from the settings and the generated registry; per
//! request it says which sides a route seals, picks the key, opens the request and seals the
//! answer.

use super::cipher::AesKey;
use super::code::{PayloadCode, PayloadError};
use super::codec::{open_json, seal_json};
use super::ecdh::{ECDH_KID, ServerKey};
use super::envelope::{self, Binding, SEALED_MEDIA_TYPE};
use super::keyring::KeyRing;
use super::mode::{self, Mode};
use super::policy::{Endpoint, find, first_inconsistent};
use super::setup::{PayloadSetupError, Settings};

/// The contract as this service enforces it.
#[derive(Debug)]
pub(crate) struct Boundary {
    mode: Mode,
    endpoints: &'static [Endpoint],
    server: Option<ServerKey>,
    ring: Option<KeyRing>,
}

/// A registered route as one request meets it: what is sealed, and the pattern the AAD names.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct Route {
    pub(crate) pattern: &'static str,
    pub(crate) opens_request: bool,
    pub(crate) seals_response: bool,
}

impl Boundary {
    /// Checks the registry, settles the mode and reads the keys; refuses to start on any of them.
    pub(crate) fn new(
        settings: &Settings<'_>,
        endpoints: &'static [Endpoint],
        config_mode: &str,
    ) -> Result<Self, PayloadSetupError> {
        if let Some(entry) = first_inconsistent(endpoints) {
            return Err(PayloadSetupError::Registry(entry.method, entry.route));
        }
        let mode = mode::resolve(settings.mode, config_mode, settings.production)?;
        let ring = KeyRing::from_sources(&settings.keys)?;
        let server = match settings
            .server_jwk
            .map(str::trim)
            .filter(|text| !text.is_empty())
        {
            Some(text) => Some(ServerKey::from_jwk_text(text).ok_or(PayloadSetupError::ServerKey)?),
            None => None,
        };
        Ok(Self {
            mode,
            endpoints,
            server,
            ring,
        })
    }

    /// The route a request matched, when the registry has it and its policy (under the switch)
    /// seals something. A GET or HEAD carries no body, so only its answer can be sealed.
    pub(crate) fn matched_route(&self, method: &str, matched: &str) -> Option<Route> {
        let entry = find(self.endpoints, method, matched)?;
        let policy = entry.policy.under(self.mode);
        let has_body = method != "GET" && method != "HEAD";
        let route = Route {
            pattern: entry.pattern,
            opens_request: policy.seals_request() && has_body,
            seals_response: policy.seals_response(),
        };
        (route.opens_request || route.seals_response).then_some(route)
    }

    /// The keys one exchange uses both ways. With `epk`, the key agreed with that public client;
    /// without it, the ring, answering under the caller's `kid` or the primary.
    pub(crate) fn exchange(
        &self,
        epk: Option<&str>,
        kid: Option<&str>,
    ) -> Result<Exchange<'_>, PayloadError> {
        if let Some(epk) = epk {
            let no_pair = PayloadError::new(PayloadCode::KeyUnknown, "this service agrees no keys");
            let server = self.server.as_ref().ok_or(no_pair)?;
            return Ok(Exchange::Agreed(Box::new(server.agree(epk)?)));
        }
        let no_key = PayloadError::new(PayloadCode::Required, "a sealed route needs x-payload-epk");
        let ring = self.ring.as_ref().ok_or(no_key)?;
        let kid = kid.unwrap_or_else(|| ring.primary_kid());
        ring.resolve(kid)?;
        Ok(Exchange::Shared {
            ring,
            kid: kid.to_owned(),
        })
    }

    /// The public key the handshake serves, when this service agrees keys at all.
    pub(crate) fn public_key(&self) -> Option<String> {
        self.server.as_ref().map(ServerKey::public_key)
    }

    /// The switch in force, which the handshake tells public clients.
    pub(crate) const fn mode(&self) -> Mode {
        self.mode
    }
}

/// The key of one exchange, in both directions.
#[derive(Debug)]
pub(crate) enum Exchange<'a> {
    /// Agreed with a public client; its envelopes carry the `ecdh` kid.
    Agreed(Box<AesKey>),
    /// The ring's key named `kid`, which the answer is sealed under.
    Shared { ring: &'a KeyRing, kid: String },
}

impl Exchange<'_> {
    /// Opens a sealed request body for `method` on `pattern`, after checking its media type.
    pub(crate) fn open_request(
        &self,
        method: &str,
        pattern: &str,
        content_type: &str,
        body: &[u8],
        now: i64,
    ) -> Result<Vec<u8>, PayloadError> {
        if !content_type.contains(SEALED_MEDIA_TYPE) {
            return Err(PayloadError::new(
                PayloadCode::Required,
                "this route takes a sealed body",
            ));
        }
        let envelope = envelope::parse(body)?;
        let key = self.key(&envelope.kid)?;
        open_json(key, &envelope, Binding::Request { method, pattern }, now)
    }

    /// Seals a JSON answer with `status` on `pattern`; returns the envelope's JSON.
    pub(crate) fn seal_response(
        &self,
        status: u16,
        pattern: &str,
        body: &[u8],
        now: i64,
    ) -> Result<Vec<u8>, PayloadError> {
        let kid = match self {
            Self::Agreed(_) => ECDH_KID,
            Self::Shared { kid, .. } => kid.as_str(),
        };
        let binding = Binding::Response { status, pattern };
        let envelope = seal_json(self.key(kid)?, kid, body, binding, now)?;
        let unwritable =
            PayloadError::new(PayloadCode::Malformed, "the envelope did not serialize");
        serde_json::to_vec(&envelope).or(Err(unwritable))
    }

    /// The key for an envelope's `kid`: the agreed key whatever it says (the AAD binds the kid),
    /// or the ring's key of that id.
    fn key(&self, kid: &str) -> Result<&AesKey, PayloadError> {
        match self {
            Self::Agreed(key) => Ok(key.as_ref()),
            Self::Shared { ring, .. } => ring.resolve(kid),
        }
    }
}

#[cfg(test)]
#[path = "boundary_tests.rs"]
mod tests;
