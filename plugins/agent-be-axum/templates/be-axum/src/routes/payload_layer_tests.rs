//! The layer through a router of its own and the client in `payload_client_tests.rs`.

use axum::body::Body;
use axum::extract::Request;
use axum::http::StatusCode;
use serde_json::{Value, json};

use super::client::{
    CLIENT_POINT, K1, NOTES, RING, SEALED, agreed, app, body, open, post_to, refusal, seal, send,
};
use crate::payload::now_millis;

#[tokio::test]
async fn a_sealed_request_reaches_the_handler_as_json_and_its_answer_leaves_sealed() {
    let note = json!({ "title": "Groceries", "tags": ["home"] });
    let envelope = seal("k1", NOTES, &note, now_millis());
    let response = send(app(Some(RING)), post_to(NOTES, SEALED), envelope).await;
    assert_eq!(response.status(), StatusCode::OK, "200");
    let answer = open(response, NOTES, K1).await;
    let expected = json!({ "type": "application/json", "body": note });
    assert_eq!(answer, expected, "the handler saw plaintext JSON");
}

#[tokio::test]
async fn a_public_client_agrees_its_key_through_epk() {
    let get = Request::get("/api/notes/7").header("x-payload-epk", CLIENT_POINT);
    let response = send(app(None), get, Body::empty()).await;
    let answer = open(response, "/api/notes/:id", agreed()).await;
    assert_eq!(answer, json!({ "id": "7" }), "sealed under the agreed key");
}

#[tokio::test]
async fn an_empty_body_passes_and_a_bodiless_answer_stays_bodiless() {
    let response = send(app(Some(RING)), post_to(NOTES, SEALED), Body::empty()).await;
    let answer = open(response, NOTES, K1).await;
    assert_eq!(answer["body"], Value::Null, "nothing to open");
    let delete = Request::delete("/api/notes/7").header("x-payload-kid", "k1");
    let response = send(app(Some(RING)), delete, Body::empty()).await;
    assert_eq!(response.status(), StatusCode::NO_CONTENT, "nothing to seal");
}

#[tokio::test]
async fn each_failure_is_refused_with_its_envelope_code() {
    let (note, now, bad) = (
        json!({ "title": "Groceries" }),
        now_millis(),
        StatusCode::BAD_REQUEST,
    );
    let fresh = seal("k1", NOTES, &note, now);
    let as_json = post_to(NOTES, "application/json");
    refusal(
        send(app(Some(RING)), as_json, fresh.clone()).await,
        bad,
        "ENVELOPE_REQUIRED",
    )
    .await;
    let no_key = send(app(None), post_to(NOTES, SEALED), fresh).await;
    refusal(no_key, bad, "ENVELOPE_REQUIRED").await;
    let cases = [
        (seal("k1", NOTES, &note, now - 120_001), "ENVELOPE_EXPIRED"),
        (seal("k9", NOTES, &note, now), "ENVELOPE_KEY_UNKNOWN"),
        (
            seal("k1", "/api/notes/:id", &note, now),
            "ENVELOPE_REJECTED",
        ),
    ];
    for (envelope, code) in cases {
        let response = send(app(Some(RING)), post_to(NOTES, SEALED), envelope).await;
        refusal(response, bad, code).await;
    }
}

#[tokio::test]
async fn half_policies_seal_one_side_and_an_unregistered_route_passes_through() {
    let upload = send(app(Some(RING)), post_to("/api/upload", "text/plain"), "[1]").await;
    assert_eq!(
        open(upload, "/api/upload", K1).await,
        json!([1]),
        "plain in, sealed out"
    );
    let note = json!({ "n": 1 });
    let envelope = seal("k1", "/api/events", &note, now_millis());
    let events = send(app(Some(RING)), post_to("/api/events", SEALED), envelope).await;
    let plain: Value = serde_json::from_slice(&body(events).await).expect("plaintext JSON");
    assert_eq!(plain["body"], note, "sealed in, plain out");
    let open_route = send(app(None), post_to("/api/open", "application/json"), "[2]").await;
    let plain: Value = serde_json::from_slice(&body(open_route).await).expect("plaintext JSON");
    assert_eq!(plain["body"], json!([2]), "not registered: untouched");
}

#[tokio::test]
async fn an_answer_that_cannot_be_sealed_or_a_body_over_the_limit_is_a_plaintext_problem() {
    let (error, large) = (StatusCode::INTERNAL_SERVER_ERROR, vec![b'x'; 512]);
    let page = send(app(Some(RING)), Request::get("/api/page"), Body::empty()).await;
    refusal(page, error, "ENVELOPE_MALFORMED").await;
    let upload = post_to("/api/upload", "text/plain");
    refusal(
        send(app(Some(RING)), upload, large.clone()).await,
        error,
        "ENVELOPE_MALFORMED",
    )
    .await;
    let too_large = send(app(Some(RING)), post_to(NOTES, SEALED), large).await;
    refusal(
        too_large,
        StatusCode::PAYLOAD_TOO_LARGE,
        "PAYLOAD_TOO_LARGE",
    )
    .await;
}
