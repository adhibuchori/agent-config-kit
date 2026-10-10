//! The contract wired into the real service: the handshake, the codes in the document, and
//! settings that do not hold.

use std::sync::Arc;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use axum::response::Response;
use base64::Engine as _;
use base64::engine::general_purpose::URL_SAFE_NO_PAD as B64;
use serde_json::Value;
use tower::ServiceExt as _;

use super::check_payload_settings;
use crate::platform::config::Config;
use crate::platform::state::AppState;
use crate::{PayloadSetupError, app, openapi, pool};

/// The service's own point for the placeholder scalar 0x11.. (Node's crypto).
const SERVER_POINT: &str =
    "BAIX5hfwtkQ5KCePlpmeaaI6TywVK99tbN9m5bgCgtTtGUp968uXcS0t2jyoWqh2Wlb0X8dYWZZS8ol8ZTBuV5Q";

fn server_jwk() -> String {
    let (d, x) = (
        B64.encode([0x11; 32]),
        "AhfmF_C2RDkoJ4-WmZ5pojpPLBUr321s32bluAKC1O0",
    );
    let y = "GUp968uXcS0t2jyoWqh2Wlb0X8dYWZZS8ol8ZTBuV5Q";
    B64.encode(format!(
        r#"{{"kty":"EC","crv":"P-256","d":"{d}","x":"{x}","y":"{y}"}}"#
    ))
}

/// The configuration with these payload variables, and a database nobody listens on.
fn config(payload: &[(&str, String)]) -> Config {
    Config::from_lookup(|key| match key {
        "DATABASE_URL" => Some("postgres://app_rw@127.0.0.1:1/none".to_owned()),
        _ => payload
            .iter()
            .find(|(name, _)| *name == key)
            .map(|(_, value)| value.clone()),
    })
    .expect("complete")
}

async fn get(config: Config, path: &str) -> (StatusCode, Option<String>, Value) {
    let state = AppState {
        pool: pool(&config).expect("a lazy pool"),
        config: Arc::new(config),
    };
    let request = Request::get(path).body(Body::empty()).expect("request");
    let response: Response = app(state).oneshot(request).await.expect("infallible");
    let cache = response
        .headers()
        .get("cache-control")
        .map(|v| v.to_str().expect("ascii").to_owned());
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .expect("body");
    (status, cache, serde_json::from_slice(&bytes).expect("JSON"))
}

#[tokio::test]
async fn the_handshake_serves_the_public_key_and_the_switch_never_cached() {
    let config = config(&[("PAYLOAD_SERVER_JWK", server_jwk())]);
    let (status, cache, body) = get(config, "/api/payload/handshake").await;
    assert_eq!(status, StatusCode::OK, "200");
    assert_eq!(
        cache.as_deref(),
        Some("no-store"),
        "every client asks afresh"
    );
    assert_eq!(body["publicKey"], SERVER_POINT, "04 || x || y, base64url");
    assert_eq!(body["mode"], "strict", "the committed switch");
}

#[tokio::test]
async fn without_a_key_pair_the_handshake_is_a_key_unknown_problem() {
    let (status, _, body) = get(config(&[]), "/api/payload/handshake").await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "400");
    assert_eq!(
        body["code"], "ENVELOPE_KEY_UNKNOWN",
        "a client cannot agree a key"
    );
}

#[tokio::test]
async fn settings_that_do_not_hold_stop_the_start_and_answer_every_route_500() {
    let broken = config(&[("PAYLOAD_KEY", "k1:short".to_owned())]);
    let refused = check_payload_settings(&broken).expect_err("a malformed key");
    assert_eq!(
        refused,
        PayloadSetupError::Key("PAYLOAD_KEY"),
        "names the variable"
    );
    let (status, _, body) = get(broken, "/api/health").await;
    assert_eq!(
        status,
        StatusCode::INTERNAL_SERVER_ERROR,
        "never served unprotected"
    );
    assert_eq!(body["code"], "INTERNAL", "a problem body");
    assert!(
        check_payload_settings(&config(&[])).is_ok(),
        "no key at all is a valid start"
    );
}

#[test]
fn the_document_lists_the_envelope_codes_after_the_service_codes() {
    let document = serde_json::to_value(openapi()).expect("serializable");
    let codes = &document["components"]["schemas"]["Problem"]["properties"]["code"]["enum"];
    let codes: Vec<&str> = codes
        .as_array()
        .expect("an enum")
        .iter()
        .filter_map(Value::as_str)
        .collect();
    let envelope = [
        "ENVELOPE_REQUIRED",
        "ENVELOPE_MALFORMED",
        "ENVELOPE_EXPIRED",
    ];
    let rest = ["ENVELOPE_KEY_UNKNOWN", "ENVELOPE_REJECTED"];
    assert!(
        codes.ends_with(&[envelope.as_slice(), rest.as_slice()].concat()),
        "{codes:?}"
    );
    assert!(codes.contains(&"INTERNAL"), "the service's own codes stay");
}
