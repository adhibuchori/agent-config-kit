//! What the layer tests share: a router of their own behind the layer, and a client written
//! straight against the crates (the way another implementation would), so a test passes only
//! when the two really interoperate.

use aes_gcm::aead::{Aead as _, Generate as _, KeyInit as _, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use axum::body::{Body, Bytes};
use axum::extract::Request;
use axum::http::request::Builder;
use axum::http::{HeaderMap, StatusCode};
use axum::response::Response;
use axum::routing::{get, post};
use axum::{Json, Router};
use base64::Engine as _;
use base64::engine::general_purpose::URL_SAFE_NO_PAD as B64;
use serde_json::{Value, json};
use tower::ServiceExt as _;
use tower_http::limit::RequestBodyLimitLayer;

use super::seal_with;
use crate::payload::{Boundary, Endpoint, Policy, Settings};

/// Placeholder key material (32 bytes of 0x07), never a real key.
pub(super) const RING: &str = "k1:BwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwc";
pub(super) const K1: [u8; 32] = [7; 32];
/// The scalar 0x22.. agrees `AGREED` with the server key 0x11.. (Node's crypto).
pub(super) const CLIENT_POINT: &str =
    "BNZak5d8qj0bCBhS_1ennkZfFmBXcwS66tUF3TpIWJzzUBheiVNy32Ih6joTdVfkc_3bZ1XwW9UHw8Uz_OnJEoU";
pub(super) const AGREED: &str = "UjnYYLy-8NnQRmwe89mifvlIAPiiK2k2GfGM-FBBGGs";
pub(super) const SEALED: &str = "application/vnd.payload-envelope+json";
pub(super) const NOTES: &str = "/api/notes";

#[rustfmt::skip]
const REGISTRY: &[Endpoint] = &[
    Endpoint { method: "POST", route: NOTES, pattern: NOTES, policy: Policy::Strict, reason: "" },
    Endpoint { method: "GET", route: "/api/notes/{id}", pattern: "/api/notes/:id", policy: Policy::Strict, reason: "" },
    Endpoint { method: "DELETE", route: "/api/notes/{id}", pattern: "/api/notes/:id", policy: Policy::Strict, reason: "" },
    Endpoint { method: "POST", route: "/api/upload", pattern: "/api/upload", policy: Policy::ResponseOnly, reason: "multipart" },
    Endpoint { method: "POST", route: "/api/events", pattern: "/api/events", policy: Policy::RequestOnly, reason: "a stream" },
    Endpoint { method: "GET", route: "/api/page", pattern: "/api/page", policy: Policy::Strict, reason: "" },
];

/// Answers what it received: the content type and the body, as JSON.
async fn echo(headers: HeaderMap, body: Bytes) -> Json<Value> {
    let kind = headers
        .get("content-type")
        .map(|v| v.to_str().unwrap_or("?").to_owned());
    let body: Value = serde_json::from_slice(&body).unwrap_or_default();
    Json(json!({ "type": kind, "body": body }))
}

/// Streams the request body back: over the limit, the answer fails while it is read.
async fn relay(request: Request) -> Response {
    Response::new(Body::from_stream(request.into_body().into_data_stream()))
}

/// The server key pair for the scalar 0x11.., as `PAYLOAD_SERVER_JWK` holds it.
fn server_jwk() -> String {
    let d = B64.encode([0x11; 32]);
    let x = "AhfmF_C2RDkoJ4-WmZ5pojpPLBUr321s32bluAKC1O0";
    let y = "GUp968uXcS0t2jyoWqh2Wlb0X8dYWZZS8ol8ZTBuV5Q";
    B64.encode(format!(
        r#"{{"kty":"EC","crv":"P-256","d":"{d}","x":"{x}","y":"{y}"}}"#
    ))
}

/// The routes above behind the layer and a 256-byte body limit, with the ring `ring`.
pub(super) fn app(ring: Option<&str>) -> Router {
    let jwk = server_jwk();
    let keys = [("PAYLOAD_KEY", ring), ("PAYLOAD_KEY_NEXT", None)];
    let (server_jwk, production) = (Some(jwk.as_str()), false);
    let settings = Settings {
        mode: None,
        keys,
        server_jwk,
        production,
    };
    let boundary = Boundary::new(&settings, REGISTRY, "strict").expect("valid");
    let note = get(|| async { Json(json!({ "id": "7" })) });
    let routes = Router::new()
        .route(NOTES, post(echo))
        .route(
            "/api/notes/{id}",
            note.delete(|| async { StatusCode::NO_CONTENT }),
        )
        .route("/api/upload", post(relay))
        .route("/api/events", post(echo))
        .route("/api/page", get(|| async { "<html>" }))
        .route("/api/open", post(echo));
    seal_with(routes, boundary).layer(RequestBodyLimitLayer::new(256))
}

/// An envelope for `POST <pattern>` under `kid`, stamped `ts`.
pub(super) fn seal(kid: &str, pattern: &str, body: &Value, ts: i64) -> String {
    let (nonce, msg) = (Nonce::generate(), body.to_string());
    let aad = format!("1.POST.{pattern}.{kid}.{ts}");
    let (msg, aad) = (msg.as_bytes(), aad.as_bytes());
    let ct = Aes256Gcm::new(&K1.into()).encrypt(&nonce, Payload { msg, aad });
    let (iv, ct) = (B64.encode(nonce), B64.encode(ct.expect("sealed")));
    json!({ "v": 1, "alg": "A256GCM", "kid": kid, "iv": iv, "ct": ct, "ts": ts }).to_string()
}

/// A sealed answer opened under `key` with the AAD its status and pattern give.
pub(super) async fn open(response: Response, pattern: &str, key: [u8; 32]) -> Value {
    let (status, headers) = (response.status().as_u16(), response.headers().clone());
    assert_eq!(headers["content-type"], SEALED, "a sealed answer");
    let vary = &headers["vary"];
    assert_eq!(
        vary, "x-payload-epk, x-payload-kid",
        "never cached across callers"
    );
    let envelope: Value = serde_json::from_slice(&body(response).await).expect("an envelope");
    let field = |name: &str| {
        B64.decode(envelope[name].as_str().expect(name))
            .expect(name)
    };
    let (kid, ts) = (envelope["kid"].as_str().expect("kid"), &envelope["ts"]);
    let aad = format!("1.{status}.{pattern}.{kid}.{ts}");
    let nonce = Nonce::try_from(field("iv").as_slice()).expect("12 bytes");
    let (msg, aad) = (&field("ct"), aad.as_bytes());
    let plain = Aes256Gcm::new(&key.into()).decrypt(&nonce, Payload { msg, aad });
    serde_json::from_slice(&plain.expect("opens")).expect("JSON")
}

/// The agreed key `AGREED` names.
pub(super) fn agreed() -> [u8; 32] {
    let bytes = B64.decode(AGREED).expect("base64url");
    bytes.try_into().expect("32 bytes")
}

pub(super) async fn body(response: Response) -> Bytes {
    let body = response.into_body();
    axum::body::to_bytes(body, usize::MAX).await.expect("body")
}

pub(super) async fn send(app: Router, request: Builder, body: impl Into<Body>) -> Response {
    let request = request.body(body.into()).expect("request");
    app.oneshot(request).await.expect("infallible")
}

pub(super) fn post_to(path: &str, media: &str) -> Builder {
    Request::post(path).header("content-type", media)
}

/// A refusal: plaintext problem+json with the code, and never the reason the log gets.
pub(super) async fn refusal(response: Response, status: StatusCode, code: &str) {
    assert_eq!(response.status(), status, "{code}");
    let media = &response.headers()["content-type"];
    assert_eq!(media, "application/problem+json", "{code} in clear");
    let problem: Value = serde_json::from_slice(&body(response).await).expect("JSON");
    assert_eq!(problem["code"], code, "the code");
    let kind = problem["type"].as_str().expect("type");
    assert!(kind.ends_with(code), "type = base + code");
    assert!(
        problem.get("detail").is_none(),
        "no internal message: {problem}"
    );
}
