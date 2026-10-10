//! The registry's types, and the one place that decides what a policy seals (Rule 30). Every
//! route is one entry carrying both halves of the contract, where it lives and what happens to
//! its body, so no route exists without a decision. The entries are generated from the spec and
//! `payload.config.json` (`endpoints_generated.rs`); a policy other than `strict` needs a reason.

use super::mode::Mode;

/// Which sides of an exchange are sealed. A half-policy names the side that cannot be sealed, and
/// its reason is a property of the body, never a judgement of how sensitive it is.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Policy {
    /// Both sides: the default for every route.
    Strict,
    /// Request plain, response sealed: a `multipart/form-data` upload.
    ResponseOnly,
    /// Request sealed, response plain: an event stream, a file a client saves or draws.
    RequestOnly,
    /// Neither: probes, the handshake, a third party's webhook.
    None,
}

impl Policy {
    /// Whether the request body is sealed. Transports call this; none compares policies itself.
    pub(crate) fn seals_request(self) -> bool {
        self == Self::Strict || self == Self::RequestOnly
    }

    /// Whether the response body is sealed.
    pub(crate) fn seals_response(self) -> bool {
        self == Self::Strict || self == Self::ResponseOnly
    }

    /// The policy in force: none at all while the switch is off.
    pub(crate) fn under(self, mode: Mode) -> Self {
        if mode == Mode::Off { Self::None } else { self }
    }
}

/// One registered route.
#[derive(Debug)]
pub(crate) struct Endpoint {
    /// Upper case, as the request AAD spells it.
    pub(crate) method: &'static str,
    /// The route as axum matched it (`MatchedPath`): `/api/things/{id}`.
    pub(crate) route: &'static str,
    /// The route as the AAD spells it: `/api/things/:id`.
    pub(crate) pattern: &'static str,
    pub(crate) policy: Policy,
    /// Why the route is not `strict`; empty when it is.
    pub(crate) reason: &'static str,
}

/// The entry a request belongs to, by its method and matched route.
pub(crate) fn find(
    endpoints: &'static [Endpoint],
    method: &str,
    route: &str,
) -> Option<&'static Endpoint> {
    endpoints
        .iter()
        .find(|entry| entry.method == method && entry.route == route)
}

/// The first entry that breaks the registry's own rules, as `METHOD route`: a pattern that is not
/// its route with `{x}` written `:x`, or a reason on a strict entry or missing from another. The
/// generator never writes one; a hand edit does, and the service refuses to start on it.
pub(crate) fn first_inconsistent(endpoints: &'static [Endpoint]) -> Option<&'static Endpoint> {
    endpoints.iter().find(|entry| {
        let pattern = entry.route.replace('{', ":").replace('}', "");
        let strict = entry.policy == Policy::Strict;
        pattern != entry.pattern || strict != entry.reason.trim().is_empty()
    })
}

#[cfg(test)]
#[path = "policy_tests.rs"]
mod tests;
