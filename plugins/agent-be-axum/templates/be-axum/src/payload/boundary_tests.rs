use super::{Boundary, Exchange, Route};
use crate::payload::cipher::AesKey;
use crate::payload::codec::{open_json, seal_json};
use crate::payload::encoding::{from_base64url, to_base64url};
use crate::payload::envelope::{Binding, Envelope, SEALED_MEDIA_TYPE};
use crate::payload::policy::{Endpoint, Policy};
use crate::payload::setup::{PayloadSetupError, Settings};
use crate::payload::{Mode, PayloadCode};

const NOW: i64 = 1_767_225_600_000;
/// Placeholder key material (32 bytes of 0x07), never a real key.
const SEVENS: &str = "k1:BwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwc";
/// A client's point for the placeholder scalar `0x22` (Node's crypto, as in `ecdh_tests.rs`).
const CLIENT_POINT: &str =
    "BNZak5d8qj0bCBhS_1ennkZfFmBXcwS66tUF3TpIWJzzUBheiVNy32Ih6joTdVfkc_3bZ1XwW9UHw8Uz_OnJEoU";
const NOTES: &str = "/api/notes";

#[rustfmt::skip]
const REGISTRY: &[Endpoint] = &[
    Endpoint { method: "POST", route: NOTES, pattern: NOTES, policy: Policy::Strict, reason: "" },
    Endpoint { method: "GET", route: "/api/notes/{id}", pattern: "/api/notes/:id", policy: Policy::Strict, reason: "" },
    Endpoint { method: "GET", route: "/api/feed", pattern: "/api/feed", policy: Policy::RequestOnly, reason: "a stream" },
    Endpoint { method: "GET", route: "/api/health", pattern: "/api/health", policy: Policy::None, reason: "a probe" },
];

#[rustfmt::skip]
const BROKEN: &[Endpoint] = &[
    Endpoint { method: "GET", route: "/a/{id}", pattern: "/a/{id}", policy: Policy::Strict, reason: "" },
];

fn jwk() -> String {
    let x = "AhfmF_C2RDkoJ4-WmZ5pojpPLBUr321s32bluAKC1O0";
    let y = "GUp968uXcS0t2jyoWqh2Wlb0X8dYWZZS8ol8ZTBuV5Q";
    let d = to_base64url(&[0x11; 32]);
    let text = format!(r#"{{"kty":"EC","crv":"P-256","d":"{d}","x":"{x}","y":"{y}"}}"#);
    to_base64url(text.as_bytes())
}

fn settings<'a>(mode: Option<&'a str>, key: Option<&'a str>, jwk: Option<&'a str>) -> Settings<'a> {
    let keys = [("PAYLOAD_KEY", key), ("PAYLOAD_KEY_NEXT", None)];
    Settings {
        mode,
        keys,
        server_jwk: jwk,
        production: false,
    }
}

fn boundary(key: Option<&str>, jwk: Option<&str>) -> Boundary {
    Boundary::new(&settings(None, key, jwk), REGISTRY, "strict").expect("valid settings")
}

/// What startup says about these settings, registry and committed switch.
fn refused(
    settings: &Settings<'_>,
    registry: &'static [Endpoint],
    mode: &str,
) -> PayloadSetupError {
    Boundary::new(settings, registry, mode).expect_err("refused")
}

fn post_notes(kid: &str, body: &[u8]) -> Vec<u8> {
    let binding = Binding::Request {
        method: "POST",
        pattern: NOTES,
    };
    let envelope = seal_json(&AesKey::new([7; 32]), kid, body, binding, NOW).expect("sealed");
    serde_json::to_vec(&envelope).expect("JSON")
}

#[test]
fn startup_refuses_a_broken_registry_switch_key_or_server_key() {
    let none = settings(None, None, None);
    let registry = refused(&none, BROKEN, "strict");
    assert_eq!(
        registry,
        PayloadSetupError::Registry("GET", "/a/{id}"),
        "the entry"
    );
    let file = "payload.config.json encryption";
    assert_eq!(
        refused(&none, REGISTRY, "on"),
        PayloadSetupError::Mode(file),
        "the switch"
    );
    let key = refused(&settings(None, Some("k1"), None), REGISTRY, "strict");
    assert_eq!(key, PayloadSetupError::Key("PAYLOAD_KEY"), "the key");
    let pair = refused(&settings(None, None, Some("e30")), REGISTRY, "strict");
    assert_eq!(pair, PayloadSetupError::ServerKey, "the key pair");
    let blank = boundary(None, Some(" "));
    assert!(blank.public_key().is_none(), "a blank JWK is no key pair");
}

#[test]
fn a_route_seals_what_its_policy_says_and_nothing_while_the_switch_is_off() {
    let strict = boundary(None, None);
    let both = Route {
        pattern: NOTES,
        opens_request: true,
        seals_response: true,
    };
    assert_eq!(
        strict.matched_route("POST", NOTES),
        Some(both),
        "both sides"
    );
    let get = Route {
        pattern: "/api/notes/:id",
        opens_request: false,
        seals_response: true,
    };
    let id = strict.matched_route("GET", "/api/notes/{id}");
    assert_eq!(id, Some(get), "a GET has no body to open");
    let feed = strict.matched_route("GET", "/api/feed");
    assert_eq!(feed, None, "request-only on a GET seals nothing");
    assert_eq!(strict.matched_route("GET", "/api/health"), None, "none");
    assert_eq!(strict.matched_route("PUT", NOTES), None, "unregistered");
    let off = Boundary::new(&settings(Some("off"), None, None), REGISTRY, "strict");
    let off = off.expect("off outside production");
    assert_eq!(
        (off.mode(), off.matched_route("POST", NOTES)),
        (Mode::Off, None),
        "off"
    );
}

#[test]
fn the_exchange_key_comes_from_epk_or_the_ring() {
    let no_keys = boundary(None, None);
    let required = no_keys.exchange(None, None).expect_err("no epk, no ring");
    assert_eq!(required.code, PayloadCode::Required, "a plaintext caller");
    let unknown = no_keys
        .exchange(Some(CLIENT_POINT), None)
        .expect_err("no pair");
    assert_eq!(
        unknown.code,
        PayloadCode::KeyUnknown,
        "epk without a key pair"
    );
    let pair = boundary(None, Some(&jwk()));
    let served = pair.public_key().expect("a key pair");
    assert!(served.starts_with("BAIX"), "the served point");
    let agreed = pair.exchange(Some(CLIENT_POINT), None);
    assert!(matches!(agreed, Ok(Exchange::Agreed(_))), "agreed");
    let bad = pair.exchange(Some("AAAA"), None).expect_err("not a point");
    assert_eq!(bad.code, PayloadCode::Malformed, "a bad epk");
    let ring = boundary(Some(SEVENS), None);
    let primary = ring.exchange(None, None).expect("primary");
    assert!(
        matches!(primary, Exchange::Shared { ref kid, .. } if kid == "k1"),
        "k1"
    );
    let named = ring.exchange(None, Some("k9")).expect_err("not held");
    assert_eq!(named.code, PayloadCode::KeyUnknown, "a kid this side lacks");
}

#[test]
fn a_sealed_request_opens_and_anything_else_is_refused_with_its_code() {
    let ring = boundary(Some(SEVENS), None);
    let exchange = ring.exchange(None, Some("k1")).expect("k1");
    let sealed = post_notes("k1", br#"{"title":"Groceries"}"#);
    let open = |media: &str, body: &[u8]| exchange.open_request("post", NOTES, media, body, NOW);
    let plaintext = open(SEALED_MEDIA_TYPE, &sealed).expect("opens");
    assert_eq!(plaintext, br#"{"title":"Groceries"}"#, "plaintext");
    let other_kid = post_notes("k2", b"1");
    let cases = [
        (open("application/json", &sealed), PayloadCode::Required),
        (open(SEALED_MEDIA_TYPE, b"{}"), PayloadCode::Required),
        (open(SEALED_MEDIA_TYPE, &other_kid), PayloadCode::KeyUnknown),
    ];
    for (result, code) in cases {
        assert_eq!(result.expect_err("refused").code, code, "{code:?}");
    }
}

#[test]
fn an_answer_is_sealed_under_the_exchange_kid_and_its_status() {
    let ring = boundary(Some(SEVENS), Some(&jwk()));
    let shared = ring.exchange(None, None).expect("primary");
    let sealed = shared
        .seal_response(201, NOTES, b"{}", NOW)
        .expect("sealed");
    let envelope: Envelope = serde_json::from_slice(&sealed).expect("an envelope");
    assert_eq!(envelope.kid, "k1", "under the caller's key");
    let binding = Binding::Response {
        status: 201,
        pattern: NOTES,
    };
    let opened = open_json(&AesKey::new([7; 32]), &envelope, binding, NOW).expect("opens");
    assert_eq!(opened, b"{}", "bound to 201");
    let agreed = ring.exchange(Some(CLIENT_POINT), None).expect("agreed");
    let sealed = agreed
        .seal_response(200, NOTES, b"[]", NOW)
        .expect("sealed");
    let envelope: Envelope = serde_json::from_slice(&sealed).expect("an envelope");
    assert_eq!(envelope.kid, "ecdh", "an agreed key's kid");
    let nonce = from_base64url(&envelope.iv).expect("base64url");
    assert_eq!(nonce.len(), 12, "a 96-bit nonce");
    let error = agreed
        .seal_response(200, NOTES, b"<html>", NOW)
        .expect_err("not JSON");
    assert_eq!(
        error.code,
        PayloadCode::Malformed,
        "an answer that is not JSON"
    );
}
