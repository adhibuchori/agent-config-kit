use std::time::Duration;

use axum::Router;
use axum::body::{Body, Bytes};
use axum::http::{Request, StatusCode};
use axum::response::Response;
use axum::routing::{get, post};
use serde_json::Value;
use tower::ServiceExt as _;

use super::super::config::Config;
use super::layers;

/// The real layers around handlers that misbehave on purpose.
fn app() -> Router {
    let config = Config::from_lookup(|key| match key {
        "DATABASE_URL" => Some("postgres://app_rw@127.0.0.1:1/none".to_owned()),
        "REQUEST_TIMEOUT_MS" => Some("50".to_owned()),
        "BODY_LIMIT_BYTES" => Some("16".to_owned()),
        "CORS_ORIGINS" => Some("https://app.example.com".to_owned()),
        _ => None,
    })
    .expect("complete");
    let router = Router::new()
        .route("/ok", get(|| async { "ok" }))
        .route("/slow", get(|| tokio::time::sleep(Duration::from_secs(5))))
        // A handler bug: indexing an empty list panics, and CatchPanicLayer answers 500.
        .route("/panic", get(|| async { Vec::<&str>::new()[0] }))
        .route("/teapot", get(|| async { StatusCode::IM_A_TEAPOT }))
        .route("/unprocessable", get(|| async { StatusCode::UNPROCESSABLE_ENTITY }))
        .route("/echo", post(|body: Bytes| async move { body }));
    layers(router, &config)
}

async fn send(request: Request<Body>) -> Response {
    app().oneshot(request).await.expect("infallible")
}

async fn problem_of(response: Response) -> Value {
    assert_eq!(
        response.headers()["content-type"],
        "application/problem+json",
        "a problem body"
    );
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .expect("body");
    serde_json::from_slice(&bytes).expect("JSON")
}

fn get_request(path: &str) -> Request<Body> {
    Request::get(path).body(Body::empty()).expect("request")
}

#[tokio::test]
async fn every_bare_error_status_becomes_a_problem_with_a_registered_code() {
    let cases = [
        ("/nowhere", StatusCode::NOT_FOUND, "ROUTE_NOT_FOUND"),
        ("/slow", StatusCode::GATEWAY_TIMEOUT, "REQUEST_TIMEOUT"),
        ("/panic", StatusCode::INTERNAL_SERVER_ERROR, "INTERNAL"),
        ("/teapot", StatusCode::IM_A_TEAPOT, "BAD_REQUEST"),
        (
            "/unprocessable",
            StatusCode::UNPROCESSABLE_ENTITY,
            "VALIDATION_FAILED",
        ),
    ];
    for (path, status, code) in cases {
        let response = send(get_request(path)).await;
        assert_eq!(response.status(), status, "{path} keeps its status");
        let id = response.headers()["x-request-id"]
            .to_str()
            .expect("ascii")
            .to_owned();
        let body = problem_of(response).await;
        assert_eq!(body["code"], code, "{path}");
        assert_eq!(
            body["requestId"],
            id.as_str(),
            "{path}: the id in the header and the body"
        );
    }
}

#[tokio::test]
async fn a_wrong_method_and_a_body_over_the_limit_are_problems_too() {
    let wrong_method = send(Request::delete("/ok").body(Body::empty()).expect("request")).await;
    assert_eq!(wrong_method.status(), StatusCode::METHOD_NOT_ALLOWED, "405");
    assert_eq!(
        problem_of(wrong_method).await["code"],
        "METHOD_NOT_ALLOWED",
        "405 code"
    );
    let too_large = Request::post("/echo")
        .header("content-length", "64")
        .body(Body::from(vec![b'x'; 64]))
        .expect("request");
    let response = send(too_large).await;
    assert_eq!(
        response.status(),
        StatusCode::PAYLOAD_TOO_LARGE,
        "413 before the body is read"
    );
    assert_eq!(
        problem_of(response).await["code"],
        "PAYLOAD_TOO_LARGE",
        "413 code"
    );
}

#[tokio::test]
async fn a_success_passes_through_untouched_with_a_request_id() {
    let response = send(get_request("/ok")).await;
    assert_eq!(response.status(), StatusCode::OK, "200");
    assert!(
        response.headers().contains_key("x-request-id"),
        "a fresh id"
    );
}

#[tokio::test]
async fn a_plain_client_id_is_kept_and_anything_else_is_replaced() {
    let kept = send(
        Request::get("/ok")
            .header("x-request-id", "client-42")
            .body(Body::empty())
            .expect("r"),
    )
    .await;
    assert_eq!(
        kept.headers()["x-request-id"],
        "client-42",
        "a plain token is kept"
    );
    let replaced = Request::get("/ok")
        .header("x-request-id", "a b\"c")
        .body(Body::empty())
        .expect("r");
    let response = send(replaced).await;
    assert_ne!(
        response.headers()["x-request-id"],
        "a b\"c",
        "anything else is replaced"
    );
}

#[tokio::test]
async fn an_allowed_origin_gets_cors_headers() {
    let request = Request::get("/ok")
        .header("origin", "https://app.example.com")
        .body(Body::empty());
    let response = send(request.expect("request")).await;
    let allowed = &response.headers()["access-control-allow-origin"];
    assert_eq!(allowed, "https://app.example.com", "the listed origin");
}
