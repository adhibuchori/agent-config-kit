use super::{open_json, seal_json};
use crate::payload::PayloadCode;
use crate::payload::cipher::{self, AesKey};
use crate::payload::encoding::to_base64url;
use crate::payload::envelope::{Binding, Envelope};

const NOW: i64 = 1_767_225_600_000;
const NOTES: Binding<'static> = Binding::Request {
    method: "POST",
    pattern: "/api/notes",
};

fn key() -> AesKey {
    AesKey::new([7; 32])
}

#[test]
fn a_json_body_seals_into_a_version_1_envelope_and_opens_back() {
    let envelope =
        seal_json(&key(), "k1", br#"{"title":"Groceries"}"#, NOTES, NOW).expect("sealed");
    assert_eq!(
        (envelope.v, envelope.alg.as_str()),
        (1, "A256GCM"),
        "version 1"
    );
    assert_eq!(
        (envelope.kid.as_str(), envelope.ts),
        ("k1", NOW),
        "kid and time"
    );
    let opened = open_json(&key(), &envelope, NOTES, NOW + 1).expect("opens");
    assert_eq!(opened, br#"{"title":"Groceries"}"#, "the body");
}

#[test]
fn a_body_that_is_not_json_is_never_sealed() {
    let error = seal_json(&key(), "k1", b"<html>", NOTES, NOW).expect_err("not JSON");
    assert_eq!(error.code, PayloadCode::Malformed, "the code");
}

#[test]
fn freshness_is_checked_before_anything_is_decrypted() {
    let mut envelope = seal_json(&key(), "k1", b"null", NOTES, NOW).expect("sealed");
    envelope.ct = "not base64!".to_owned();
    let error = open_json(&key(), &envelope, NOTES, NOW + 120_001).expect_err("stale");
    assert_eq!(
        error.code,
        PayloadCode::Expired,
        "expired, though the ciphertext is broken"
    );
}

#[test]
fn a_field_that_is_not_base64url_or_a_foreign_binding_is_rejected() {
    let sealed = seal_json(&key(), "k1", b"[]", NOTES, NOW).expect("sealed");
    let bad_iv = Envelope {
        iv: "%%".to_owned(),
        ..sealed.clone()
    };
    let bad_ct = Envelope {
        ct: "%%".to_owned(),
        ..sealed.clone()
    };
    let other = Binding::Request {
        method: "PUT",
        pattern: "/api/notes",
    };
    let refusals = [
        open_json(&key(), &bad_iv, NOTES, NOW),
        open_json(&key(), &bad_ct, NOTES, NOW),
        open_json(&key(), &sealed, other, NOW),
    ];
    for refusal in refusals {
        assert_eq!(
            refusal.expect_err("refused").code,
            PayloadCode::Rejected,
            "rejected"
        );
    }
}

#[test]
fn plaintext_that_is_not_json_is_malformed() {
    let (iv, ct) = cipher::seal(&key(), b"<html>", &NOTES.aad("k1", NOW)).expect("sealed");
    let envelope = Envelope {
        v: 1,
        alg: "A256GCM".to_owned(),
        kid: "k1".to_owned(),
        iv: to_base64url(&iv),
        ct: to_base64url(&ct),
        ts: NOW,
    };
    let error = open_json(&key(), &envelope, NOTES, NOW).expect_err("not JSON");
    assert_eq!(error.code, PayloadCode::Malformed, "opened, but not JSON");
}
