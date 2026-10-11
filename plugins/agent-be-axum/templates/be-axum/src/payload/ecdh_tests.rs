//! Unit tests of the server key and the key agreement. The expected values come from Node's
//! `crypto` (`createECDH('prime256v1')`, `hkdfSync`), an implementation independent of this one,
//! for the placeholder scalars `0x11` and `0x22` repeated 32 times.

use p256::SecretKey;

use super::{HKDF_INFO, ServerKey, derive_key_bytes, shared_secret};
use crate::payload::PayloadCode;
use crate::payload::encoding::{from_base64url, to_base64url};

const SERVER_X: &str = "AhfmF_C2RDkoJ4-WmZ5pojpPLBUr321s32bluAKC1O0";
const SERVER_Y: &str = "GUp968uXcS0t2jyoWqh2Wlb0X8dYWZZS8ol8ZTBuV5Q";
const SERVER_POINT: &str =
    "BAIX5hfwtkQ5KCePlpmeaaI6TywVK99tbN9m5bgCgtTtGUp968uXcS0t2jyoWqh2Wlb0X8dYWZZS8ol8ZTBuV5Q";
const CLIENT_POINT: &str =
    "BNZak5d8qj0bCBhS_1ennkZfFmBXcwS66tUF3TpIWJzzUBheiVNy32Ih6joTdVfkc_3bZ1XwW9UHw8Uz_OnJEoU";
const SECRET: &str = "zPwmH1gZPJjKStSlO7rG8O4pvE1IQ4CQRGkIYiynmvY";
const KEY: &str = "UjnYYLy-8NnQRmwe89mifvlIAPiiK2k2GfGM-FBBGGs";

/// `PAYLOAD_SERVER_JWK` text for the members given.
fn jwk(members: &str) -> String {
    to_base64url(format!("{{{members}}}").as_bytes())
}

fn server_jwk(y: &str) -> String {
    let d = to_base64url(&[0x11; 32]);
    jwk(&format!(
        r#""kty":"EC","crv":"P-256","d":"{d}","x":"{SERVER_X}","y":"{y}""#
    ))
}

fn decoded(text: &str) -> Vec<u8> {
    from_base64url(text).expect("base64url")
}

#[test]
fn a_server_key_reads_from_jwk_text_and_serves_its_public_point() {
    let key = ServerKey::from_jwk_text(&server_jwk(SERVER_Y)).expect("a valid JWK");
    assert_eq!(key.public_key(), SERVER_POINT, "04 || x || y, base64url");
    assert_eq!(
        format!("{key:?}"),
        format!("ServerKey({SERVER_POINT})"),
        "never d"
    );
}

#[test]
fn both_sides_agree_the_same_secret_and_key() {
    let server = SecretKey::from_slice(&[0x11; 32]).expect("scalar");
    let client = SecretKey::from_slice(&[0x22; 32]).expect("scalar");
    let one = shared_secret(&server, &decoded(CLIENT_POINT)).expect("agreed");
    let other = shared_secret(&client, &decoded(SERVER_POINT)).expect("agreed");
    assert_eq!(
        one.raw_secret_bytes().as_slice(),
        decoded(SECRET),
        "the x-coordinate"
    );
    assert_eq!(
        other.raw_secret_bytes().as_slice(),
        decoded(SECRET),
        "from either side"
    );
    let key = derive_key_bytes(&one).expect("derived");
    assert_eq!(
        key.to_vec(),
        decoded(KEY),
        "HKDF-SHA-256, empty salt, the v1 label"
    );
    assert_eq!(
        HKDF_INFO, b"payload-envelope/v1/browser",
        "the label every peer uses"
    );
    let server_key = ServerKey::from_jwk_text(&server_jwk(SERVER_Y)).expect("valid");
    assert!(
        server_key.agree(CLIENT_POINT).is_ok(),
        "the server agrees through epk"
    );
}

#[test]
fn a_jwk_that_is_not_a_matching_p256_private_key_is_refused() {
    let d = to_base64url(&[0x11; 32]);
    let refused = [
        "not base64!".to_owned(),
        to_base64url(b"not json"),
        jwk(&format!(
            r#""kty":"RSA","crv":"P-256","d":"{d}","x":"{SERVER_X}","y":"{SERVER_Y}""#
        )),
        jwk(&format!(
            r#""kty":"EC","crv":"P-384","d":"{d}","x":"{SERVER_X}","y":"{SERVER_Y}""#
        )),
        jwk(&format!(
            r#""kty":"EC","crv":"P-256","d":"AQ","x":"{SERVER_X}","y":"{SERVER_Y}""#
        )),
        jwk(&format!(
            r#""kty":"EC","crv":"P-256","d":"{d}","x":"{SERVER_X}","y":"{SERVER_Y}","ext":true"#
        )),
        server_jwk(SERVER_X),
        server_jwk("AQ"),
    ];
    for text in refused {
        assert!(ServerKey::from_jwk_text(&text).is_none(), "refused: {text}");
    }
    let zero = jwk(&format!(
        r#""kty":"EC","crv":"P-256","d":"{}","x":"{SERVER_X}","y":"{SERVER_Y}""#,
        to_base64url(&[0; 32])
    ));
    assert!(ServerKey::from_jwk_text(&zero).is_none(), "a zero scalar");
}

#[test]
fn a_peer_key_that_is_not_an_uncompressed_p256_point_is_malformed() {
    let server = ServerKey::from_jwk_text(&server_jwk(SERVER_Y)).expect("valid");
    let mut off_curve = decoded(CLIENT_POINT);
    off_curve[64] ^= 1;
    let refused = [
        "not base64!".to_owned(),
        to_base64url(&decoded(CLIENT_POINT)[1..]),
        "A9Zak5d8qj0bCBhS_1ennkZfFmBXcwS66tUF3TpIWJzz".to_owned(),
        to_base64url(&off_curve),
    ];
    for epk in refused {
        let error = server.agree(&epk).expect_err("refused");
        assert_eq!(error.code, PayloadCode::Malformed, "{epk}");
    }
}
