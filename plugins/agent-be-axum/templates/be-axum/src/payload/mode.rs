//! The switch: whether this service enforces the contract (Rule 33). `PAYLOAD_MODE` wins, then
//! `encryption` in the committed `payload.config.json` (baked into the generated registry as
//! `CONFIG_MODE`), then `strict`. `off` exists to bisect a transport problem on your own machine
//! and is refused in production at startup, so a branch merged with the switch flipped fails to
//! boot instead of serving plaintext. A client never reads either source: the handshake tells it.

use serde::Serialize;

use super::setup::PayloadSetupError;

/// How the boundary behaves.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, utoipa::ToSchema)]
#[serde(rename_all = "lowercase")]
pub(crate) enum Mode {
    /// Every registered route seals what its policy says.
    Strict,
    /// Every route passes through in plaintext; never in production.
    Off,
}

/// Settles the mode from the variable and the committed switch, trimmed, in any case, and never
/// guessing a typo into `strict`.
pub(crate) fn resolve(
    from_env: Option<&str>,
    from_config: &str,
    production: bool,
) -> Result<Mode, PayloadSetupError> {
    let env = from_env.map(str::trim).filter(|value| !value.is_empty());
    let (source, raw) = match env {
        Some(value) => ("PAYLOAD_MODE", value),
        None => ("payload.config.json encryption", from_config.trim()),
    };
    let mode = match raw.to_ascii_lowercase().as_str() {
        "strict" => Mode::Strict,
        "off" => Mode::Off,
        _ => return Err(PayloadSetupError::Mode(source)),
    };
    if mode == Mode::Off && production {
        return Err(PayloadSetupError::OffInProduction(source));
    }
    Ok(mode)
}

#[cfg(test)]
#[path = "mode_tests.rs"]
mod tests;
