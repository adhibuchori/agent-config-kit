//! What the boundary is built from at startup, and why it refuses to start. Every message names
//! the variable or the file to fix, never the value it holds (Rule 32).

/// The payload variables as `platform::config` read them, raw. No `Debug`: it holds secrets.
#[derive(Clone, Copy)]
pub(crate) struct Settings<'a> {
    /// `PAYLOAD_MODE`: `strict` or `off`; unset defers to the committed switch.
    pub(crate) mode: Option<&'a str>,
    /// `PAYLOAD_KEY` then `PAYLOAD_KEY_NEXT`, each `kid:base64key`, for server callers.
    pub(crate) keys: [(&'static str, Option<&'a str>); 2],
    /// `PAYLOAD_SERVER_JWK`: the key pair public clients agree keys with.
    pub(crate) server_jwk: Option<&'a str>,
    /// `APP_ENV=production`: `off` is refused then.
    pub(crate) production: bool,
}

/// Why the payload settings are refused. The service does not start on one (`main.rs` calls
/// `check_payload_settings`), and a router built anyway answers every route with a 500.
#[derive(Debug, PartialEq, Eq, thiserror::Error)]
pub enum PayloadSetupError {
    /// The switch is neither `strict` nor `off`.
    #[error("{0} must be \"strict\" or \"off\"")]
    Mode(&'static str),
    /// The switch is `off` in production.
    #[error("{0} is \"off\", which is refused in production")]
    OffInProduction(&'static str),
    /// A key variable is not `kid:base64key`.
    #[error(
        "{0} must be \"kid:base64key\": a kid of 1 to 32 letters, digits, '.', '_' or '-' other than \"ecdh\", and 32 bytes of key"
    )]
    Key(&'static str),
    /// A key variable repeats a kid an earlier one uses.
    #[error("{0} repeats the kid of another payload key")]
    DuplicateKid(&'static str),
    /// The server key is not a P-256 private JWK whose public half matches its private half.
    #[error("PAYLOAD_SERVER_JWK must be base64url text of a P-256 private JWK (kty, crv, d, x, y)")]
    ServerKey,
    /// A registry entry was edited by hand into one that breaks its rules.
    #[error(
        "the payload registry entry {0} {1} is inconsistent; regenerate it with node scripts/generate/payload-registry.mjs"
    )]
    Registry(&'static str, &'static str),
}

#[cfg(test)]
#[path = "setup_tests.rs"]
mod tests;
