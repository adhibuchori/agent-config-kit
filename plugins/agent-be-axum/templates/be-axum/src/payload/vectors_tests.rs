//! The shared known answers, `scripts/check/payload-vectors.json`, identical in every repo that
//! speaks the format: this copy's AAD, cipher and key agreement against them (Rule 34). Never
//! regenerate the file to make this pass: a mismatch means this copy drifted from the others.

use p256::SecretKey;
use serde_json::Value;

use super::cipher::{AesKey, open};
use super::ecdh::{HKDF_INFO, ServerKey, derive_key_bytes, shared_secret};
use super::encoding::from_base64url;
use super::envelope::{request_aad, response_aad};
use crate::platform::error::WireCode as _;

const FILE: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/scripts/check/payload-vectors.json"
);

fn file() -> Value {
    let text =
        std::fs::read_to_string(FILE).expect("scripts/check/payload-vectors.json from the kit");
    serde_json::from_str(&text).expect("JSON")
}

fn text(value: &Value) -> &str {
    value.as_str().expect("a string")
}

fn bytes(value: &Value) -> Vec<u8> {
    from_base64url(text(value)).expect("base64url")
}

fn list<'a>(file: &'a Value, key: &str) -> &'a Vec<Value> {
    let list = file[key]
        .as_array()
        .expect("a list the kit's current file has");
    assert!(
        !list.is_empty(),
        "{key} is empty: copy the kit's current file"
    );
    list
}

/// This implementation's AAD for a vector.
fn aad(vector: &Value) -> Vec<u8> {
    let (pattern, kid) = (text(&vector["pattern"]), text(&vector["kid"]));
    let ts = vector["ts"].as_i64().expect("ts");
    if vector["kind"] == "request" {
        return request_aad(text(&vector["method"]), pattern, kid, ts);
    }
    let status = u16::try_from(vector["status"].as_u64().expect("status")).expect("a status");
    response_aad(status, pattern, kid, ts)
}

/// The vector's `ct` opened under `key` and `aad` and parsed (`None` when it is not JSON), or
/// the refusal's wire code.
fn opened(key: &AesKey, vector: &Value, aad: &[u8]) -> Result<Option<Value>, &'static str> {
    match open(key, &bytes(&vector["iv"]), &bytes(&vector["ct"]), aad) {
        Ok(plaintext) => Ok(serde_json::from_slice(&plaintext).ok()),
        Err(error) => Err(error.code.as_str()),
    }
}

/// A vector's AAD is this one, byte for byte, and its `ct` opens to its `plaintext`.
fn assert_vector(key: &AesKey, vector: &Value) {
    let name = &vector["name"];
    let aad = aad(vector);
    assert_eq!(aad, text(&vector["aad"]).as_bytes(), "{name}: the AAD");
    let plaintext = Some(vector["plaintext"].clone());
    assert_eq!(opened(key, vector, &aad), Ok(plaintext), "{name}: opens");
}

fn test_key(file: &Value) -> AesKey {
    AesKey::new(bytes(&file["testBytes"]).try_into().expect("32 bytes"))
}

#[test]
fn every_vector_has_this_aad_and_opens_to_its_plaintext() {
    let file = file();
    for vector in list(&file, "vectors") {
        assert_vector(&test_key(&file), vector);
    }
}

#[test]
fn every_replay_is_rejected() {
    let file = file();
    let vectors = list(&file, "vectors");
    for reject in list(&file, "rejects") {
        let vector = vectors
            .iter()
            .find(|v| v["name"] == reject["vector"])
            .expect("named vector");
        let refused = opened(&test_key(&file), vector, text(&reject["aad"]).as_bytes());
        assert_eq!(
            refused,
            Err("ENVELOPE_REJECTED"),
            "{}: {}",
            reject["name"],
            reject["why"]
        );
    }
}

#[test]
fn every_agreement_derives_its_secret_both_ways_its_key_and_opens_its_vector() {
    let file = file();
    for agreement in list(&file, "agreements") {
        let name = &agreement["name"];
        assert_eq!(
            text(&agreement["info"]).as_bytes(),
            HKDF_INFO,
            "{name}: the HKDF label"
        );
        let server = ServerKey::from_jwk_text(text(&agreement["serverJwk"])).expect("serverJwk");
        let public = from_base64url(&server.public_key());
        assert_eq!(
            public,
            Some(bytes(&agreement["serverPublic"])),
            "{name}: the served point"
        );
        let jwk: Value = serde_json::from_slice(&bytes(&agreement["serverJwk"])).expect("JWK");
        let server_d = SecretKey::from_slice(&bytes(&jwk["d"])).expect("d");
        let client_d =
            SecretKey::from_slice(&bytes(&agreement["clientPrivate"])).expect("client d");
        let one = shared_secret(&server_d, &bytes(&agreement["clientPublic"])).expect("agreed");
        let other = shared_secret(&client_d, &bytes(&agreement["serverPublic"])).expect("agreed");
        let secret = bytes(&agreement["sharedBytes"]);
        assert_eq!(
            one.raw_secret_bytes().as_slice(),
            secret,
            "{name}: server side"
        );
        assert_eq!(
            other.raw_secret_bytes().as_slice(),
            secret,
            "{name}: client side"
        );
        let key = derive_key_bytes(&one).expect("derived");
        assert_eq!(
            key.to_vec(),
            bytes(&agreement["sessionBytes"]),
            "{name}: the derived key"
        );
        assert_vector(&AesKey::new(key), &agreement["vector"]);
        assert!(
            server.agree(text(&agreement["clientPublic"])).is_ok(),
            "{name}: through epk"
        );
    }
}

#[test]
fn every_point_reject_is_refused_with_its_code() {
    let file = file();
    let agreement = &list(&file, "agreements")[0];
    let server = ServerKey::from_jwk_text(text(&agreement["serverJwk"])).expect("serverJwk");
    for reject in list(&file, "pointRejects") {
        let code = server
            .agree(text(&reject["point"]))
            .expect_err("refused")
            .code
            .as_str();
        assert_eq!(code, text(&reject["code"]), "{}", reject["name"]);
    }
}
