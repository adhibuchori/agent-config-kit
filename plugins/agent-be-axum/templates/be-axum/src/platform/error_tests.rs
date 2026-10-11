use axum::http::StatusCode;
use axum::http::header::{CONTENT_TYPE, RETRY_AFTER};
use axum::response::{IntoResponse, Response};
use serde_json::{Value, json};

use super::{
    AppError, ErrorCode, PROBLEM_TYPE_BASE, ProblemTypeBaseError, REQUEST_ID, WireCode as _,
    check_base, check_problem_type_base, problem,
};

const EVERY_CODE: [ErrorCode; 8] = [
    ErrorCode::BadRequest,
    ErrorCode::ValidationFailed,
    ErrorCode::RouteNotFound,
    ErrorCode::MethodNotAllowed,
    ErrorCode::PayloadTooLarge,
    ErrorCode::RequestTimeout,
    ErrorCode::DatabaseUnavailable,
    ErrorCode::Internal,
];

async fn body(response: Response) -> Value {
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .expect("body");
    serde_json::from_slice(&bytes).expect("a JSON body")
}

#[test]
fn every_code_spells_its_type_from_the_base_and_its_wire_name() {
    for code in EVERY_CODE {
        let wire = serde_json::to_value(code).expect("serializable");
        assert_eq!(
            wire,
            json!(code.as_str()),
            "as_str matches the serialized code"
        );
        assert_eq!(
            code.type_uri(),
            format!("{PROBLEM_TYPE_BASE}{}", code.as_str()),
            "type"
        );
        assert!(!code.title().is_empty(), "{code:?} has a title");
        let name = code.as_str();
        assert!(
            name.bytes().all(|b| b.is_ascii_uppercase() || b == b'_'),
            "{name} is SCREAMING_SNAKE"
        );
    }
}

#[tokio::test]
async fn a_problem_carries_type_title_status_code_and_the_request_id() {
    let response = REQUEST_ID
        .scope("req-1".to_owned(), async {
            problem(StatusCode::NOT_FOUND, ErrorCode::RouteNotFound, Vec::new())
        })
        .await;
    assert_eq!(
        response.status(),
        StatusCode::NOT_FOUND,
        "the status it was given"
    );
    assert_eq!(
        response.headers()[CONTENT_TYPE],
        "application/problem+json",
        "media type"
    );
    assert!(
        !response.headers().contains_key(RETRY_AFTER),
        "no Retry-After on a 404"
    );
    let expected = json!({
        "type": format!("{PROBLEM_TYPE_BASE}ROUTE_NOT_FOUND"),
        "title": "No such route",
        "status": 404,
        "code": "ROUTE_NOT_FOUND",
        "requestId": "req-1",
    });
    assert_eq!(
        body(response).await,
        expected,
        "the whole body, nothing more"
    );
}

#[tokio::test]
async fn outside_a_request_the_body_has_no_request_id() {
    let response = problem(StatusCode::BAD_REQUEST, ErrorCode::BadRequest, Vec::new());
    assert!(
        body(response).await.get("requestId").is_none(),
        "no requestId member"
    );
}

#[tokio::test]
async fn an_unavailable_database_answers_503_with_retry_after_and_no_internal_text() {
    let error = AppError::DatabaseUnavailable(sqlx::Error::PoolClosed);
    assert!(
        error.to_string().starts_with("the database did not answer"),
        "a log message"
    );
    let response = error.into_response();
    assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE, "503");
    assert_eq!(
        response.headers()[RETRY_AFTER],
        "5",
        "tells the client when to retry"
    );
    let text = body(response).await.to_string();
    assert!(text.contains("DATABASE_UNAVAILABLE"), "the code: {text}");
    assert!(!text.contains("pool"), "never the internal message: {text}");
}

#[test]
fn a_base_is_an_absolute_normalized_https_url_ending_in_a_slash() {
    let ok = "https://api.example.com/problems/";
    assert_eq!(
        check_base(ok, true),
        Ok(()),
        "a real base passes in production"
    );
    for bad in [
        "http://api.example.com/problems/",
        "/problems/",
        "https://api.example.com/problems",
        "https://api.example.com",
        "https:///problems/",
        "https://API.example.com/problems/",
        "https://api.example.com/problems/?v=1",
        "https://api.example.com/problems/#top",
        "https://api.example.com/a/../problems/",
        "https://api.example.com/a//problems/",
    ] {
        assert_eq!(
            check_base(bad, false),
            Err(ProblemTypeBaseError::Malformed),
            "refused: {bad}"
        );
    }
}

#[test]
fn the_placeholder_passes_everywhere_but_production() {
    let placeholder = "https://example.invalid/problems/";
    assert_eq!(
        check_base(placeholder, false),
        Ok(()),
        "fine in development and CI"
    );
    let refused = check_base(placeholder, true);
    assert_eq!(
        refused,
        Err(ProblemTypeBaseError::Placeholder),
        "refused in production"
    );
    let still_placeholder = PROBLEM_TYPE_BASE.contains(".invalid/");
    assert_eq!(
        check_problem_type_base(true).is_err(),
        still_placeholder,
        "the committed base"
    );
    assert_eq!(
        check_problem_type_base(false),
        Ok(()),
        "the committed base is well formed"
    );
}

#[test]
fn each_refusal_says_what_to_fix() {
    let malformed = ProblemTypeBaseError::Malformed.to_string();
    assert!(malformed.contains("absolute https URL"), "{malformed}");
    let placeholder = ProblemTypeBaseError::Placeholder.to_string();
    assert!(placeholder.contains("PROBLEM_TYPE_BASE"), "{placeholder}");
}
