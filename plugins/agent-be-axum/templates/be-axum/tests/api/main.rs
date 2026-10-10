//! Handler tier: the real router and layers through `oneshot`, the way a client meets them, with a
//! pool that never connects (Rule 26).
#![cfg(test)]

mod openapi;

use std::sync::Arc;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use axum::response::Response;
use serde_json::Value;
use service::{AppState, Config, app, pool};
use tower::ServiceExt as _;

/// A database nobody listens on, and a short wait for it.
fn config() -> Config {
    Config::from_lookup(|key| match key {
        "DATABASE_URL" => Some("postgres://app_rw@127.0.0.1:1/none".to_owned()),
        "DB_ACQUIRE_TIMEOUT_MS" => Some("250".to_owned()),
        _ => None,
    })
    .expect("the test configuration is complete")
}

async fn get(path: &str) -> Response {
    let config = config();
    let state = AppState {
        pool: pool(&config).expect("a lazy pool"),
        config: Arc::new(config),
    };
    let request = Request::get(path).body(Body::empty()).expect("request");
    app(state).oneshot(request).await.expect("infallible")
}

async fn json(response: Response) -> Value {
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .expect("body");
    serde_json::from_slice(&bytes).expect("a JSON body")
}

#[tokio::test]
async fn health_answers_without_the_database() {
    let response = get("/api/health").await;
    assert_eq!(response.status(), StatusCode::OK, "200");
    assert_eq!(
        json(response).await["status"],
        "ok",
        "the body the spec declares"
    );
}

#[tokio::test]
async fn ready_answers_503_with_a_problem_when_the_database_does_not() {
    let response = get("/api/ready").await;
    assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE, "503");
    let id = response.headers()["x-request-id"]
        .to_str()
        .expect("ascii")
        .to_owned();
    let body = json(response).await;
    assert_eq!(body["code"], "DATABASE_UNAVAILABLE", "the registered code");
    assert_eq!(
        body["requestId"],
        id.as_str(),
        "the id the client can quote"
    );
    let kind = body["type"].as_str().expect("a type");
    assert!(
        kind.ends_with("/DATABASE_UNAVAILABLE"),
        "type = base + code: {kind}"
    );
}

#[tokio::test]
async fn an_unknown_route_is_a_problem() {
    let response = get("/api/nowhere").await;
    assert_eq!(response.status(), StatusCode::NOT_FOUND, "404");
    assert_eq!(
        json(response).await["code"],
        "ROUTE_NOT_FOUND",
        "the registered code"
    );
}
