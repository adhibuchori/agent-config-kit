use super::{
    Binding, ENVELOPE_ALG, Envelope, MAX_CLOCK_SKEW_MS, is_fresh, now_millis, parse, request_aad,
    response_aad,
};
use crate::payload::PayloadCode;

const VALID: &str =
    r#"{"v":1,"alg":"A256GCM","kid":"k1","iv":"aXY","ct":"Y3Q","ts":1767225600000}"#;

#[test]
fn a_well_formed_envelope_is_read_field_by_field() {
    let envelope = parse(VALID.as_bytes()).expect("well formed");
    let expected = Envelope {
        v: 1,
        alg: ENVELOPE_ALG.to_owned(),
        kid: "k1".to_owned(),
        iv: "aXY".to_owned(),
        ct: "Y3Q".to_owned(),
        ts: 1_767_225_600_000,
    };
    assert_eq!(envelope, expected, "every field");
}

#[test]
fn anything_but_a_version_1_envelope_is_refused_as_plaintext() {
    let refused = [
        r#"{"title":"Groceries"}"#,
        r#"{"v":2,"alg":"A256GCM","kid":"k1","iv":"aXY","ct":"Y3Q","ts":1}"#,
        r#"{"v":1,"alg":"A128GCM","kid":"k1","iv":"aXY","ct":"Y3Q","ts":1}"#,
        r#"{"v":1,"alg":"A256GCM","kid":"k1","iv":"aXY","ct":"Y3Q","ts":1.5}"#,
        r#"{"v":1,"alg":"A256GCM","kid":"k1","iv":"aXY","ct":"Y3Q","ts":1,"x":0}"#,
        r#"{"v":1,"alg":"A256GCM","kid":"k1","iv":"aXY","ts":1}"#,
        "not json",
    ];
    for body in refused {
        let error = parse(body.as_bytes()).expect_err(body);
        assert_eq!(error.code, PayloadCode::Required, "{body}");
    }
}

#[test]
fn the_window_is_two_minutes_either_way() {
    let now = 1_767_225_600_000;
    let skew = i64::try_from(MAX_CLOCK_SKEW_MS).expect("small");
    assert_eq!(skew, 120_000, "the contract's window");
    assert!(is_fresh(now - skew, now), "the oldest accepted");
    assert!(is_fresh(now + skew, now), "the latest accepted");
    assert!(!is_fresh(now - skew - 1, now), "a millisecond too old");
    assert!(
        !is_fresh(now + skew + 1, now),
        "a millisecond in the future"
    );
}

#[test]
fn now_is_in_epoch_milliseconds() {
    assert!(
        now_millis() > 1_767_225_600_000,
        "after 2026-01-01 in milliseconds"
    );
}

#[test]
fn the_aad_names_version_method_or_status_pattern_kid_and_time() {
    let request = request_aad("post", "/api/notes/:id", "k1", 1_767_225_600_000);
    assert_eq!(
        request, b"1.POST./api/notes/:id.k1.1767225600000",
        "method upper case"
    );
    let response = response_aad(201, "/api/notes/:id", "ecdh", 7);
    assert_eq!(response, b"1.201./api/notes/:id.ecdh.7", "the status");
    let bound = Binding::Request {
        method: "DELETE",
        pattern: "/api/notes/:id",
    };
    assert_eq!(
        bound.aad("k1", 7),
        b"1.DELETE./api/notes/:id.k1.7",
        "a request binding"
    );
    let bound = Binding::Response {
        status: 204,
        pattern: "/api/notes",
    };
    assert_eq!(
        bound.aad("k1", 7),
        b"1.204./api/notes.k1.7",
        "a response binding"
    );
}
