use axum::body::Body;
use axum::extract::{FromRequest, Request};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde::Deserialize;
use serde_json::Value;

use super::{BodyRejection, ValidJson};

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
struct Order {
    quantity: u32,
}

fn request(content_type: &str, body: impl Into<Body>) -> Request {
    Request::post("/")
        .header("content-type", content_type)
        .body(body.into())
        .expect("request")
}

async fn read(request: Request) -> Result<Order, BodyRejection> {
    ValidJson::<Order>::from_request(request, &())
        .await
        .map(|ValidJson(order)| order)
}

async fn refusal(request: Request) -> (StatusCode, Value) {
    let response: Response = read(request).await.expect_err("refused").into_response();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .expect("body");
    (
        status,
        serde_json::from_slice(&bytes).expect("a problem body"),
    )
}

#[tokio::test]
async fn a_valid_body_is_read() {
    let order = read(request("application/json", r#"{"quantity": 3}"#))
        .await
        .expect("valid");
    assert_eq!(order, Order { quantity: 3 }, "the body as sent");
}

#[tokio::test]
async fn a_wrong_type_names_the_field_and_never_echoes_the_value() {
    let (status, body) =
        refusal(request("application/json", r#"{"quantity": "secret-123"}"#)).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "422");
    assert_eq!(body["code"], "VALIDATION_FAILED", "the registered code");
    assert_eq!(body["fields"][0]["field"], "quantity", "names the field");
    assert_eq!(
        body["fields"][0]["code"], "INVALID",
        "a field code, not a message"
    );
    assert!(
        !body.to_string().contains("secret-123"),
        "never the value: {body}"
    );
}

#[tokio::test]
async fn an_unknown_field_is_refused() {
    let (status, body) = refusal(request(
        "application/json",
        r#"{"quantity": 1, "extra": 2}"#,
    ))
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "422");
    assert_eq!(
        body["fields"][0]["field"], "extra",
        "names the unknown field"
    );
}

#[tokio::test]
async fn trailing_characters_and_a_non_json_type_are_refused_as_the_body() {
    for refused in [
        request("application/json", r#"{"quantity": 1} x"#),
        request("text/plain", "{}"),
    ] {
        let (status, body) = refusal(refused).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "422");
        assert_eq!(body["fields"][0]["field"], "$body", "the whole body");
    }
}

#[tokio::test]
async fn a_body_over_the_limit_answers_413() {
    let big = vec![b' '; 3 * 1024 * 1024];
    let (status, body) = refusal(request("application/json", big)).await;
    assert_eq!(status, StatusCode::PAYLOAD_TOO_LARGE, "413");
    assert_eq!(body["code"], "PAYLOAD_TOO_LARGE", "the registered code");
}
