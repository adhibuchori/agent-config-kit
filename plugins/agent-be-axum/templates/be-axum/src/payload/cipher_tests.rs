use super::{AesKey, IV_BYTES, open, seal};
use crate::payload::PayloadCode;

/// Placeholder key material, never a real key.
fn key() -> AesKey {
    AesKey::new([7; 32])
}

#[test]
fn a_sealed_body_opens_under_its_key_and_aad() {
    let (iv, sealed) = seal(&key(), b"{\"a\":1}", b"aad").expect("sealed");
    assert_eq!(iv.len(), IV_BYTES, "a 96-bit nonce");
    assert_eq!(sealed.len(), 7 + 16, "the ciphertext and a 16-byte tag");
    let opened = open(&key(), &iv, &sealed, b"aad").expect("opens");
    assert_eq!(opened, b"{\"a\":1}", "the plaintext");
}

#[test]
fn every_seal_takes_a_fresh_nonce() {
    let (first, _) = seal(&key(), b"1", b"aad").expect("sealed");
    let (second, _) = seal(&key(), b"1", b"aad").expect("sealed");
    assert_ne!(first, second, "never one nonce twice under a key");
}

#[test]
fn another_aad_another_key_or_a_short_nonce_is_rejected_alike() {
    let (iv, sealed) = seal(&key(), b"1", b"aad").expect("sealed");
    let other_key = AesKey::new([9; 32]);
    let refusals = [
        open(&key(), &iv, &sealed, b"another aad"),
        open(&other_key, &iv, &sealed, b"aad"),
        open(&key(), &iv[..8], &sealed, b"aad"),
    ];
    for refusal in refusals {
        let error = refusal.expect_err("refused");
        assert_eq!(
            error.code,
            PayloadCode::Rejected,
            "one code for every failure"
        );
    }
}

#[test]
fn a_key_never_prints_itself() {
    assert_eq!(
        format!("{:?}", key()),
        "AesKey(..)",
        "no key material in a log line"
    );
}
