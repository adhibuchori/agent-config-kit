use super::KeyRing;
use crate::payload::PayloadCode;
use crate::payload::setup::PayloadSetupError;

/// 32 bytes of 0x07 and of 0x09, standard and url-safe: placeholder material, never a real key.
const SEVENS: &str = "BwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwc=";
const NINES: &str = "CQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQk";

fn ring(primary: Option<&str>, next: Option<&str>) -> Result<Option<KeyRing>, PayloadSetupError> {
    KeyRing::from_sources(&[("PAYLOAD_KEY", primary), ("PAYLOAD_KEY_NEXT", next)])
}

#[test]
fn no_configured_key_is_no_ring() {
    assert!(ring(None, None).expect("fine").is_none(), "unset");
    assert!(ring(Some("  "), None).expect("fine").is_none(), "blank");
}

#[test]
fn the_first_key_seals_and_every_key_opens() {
    let primary = format!("k1:{SEVENS}");
    let next = format!(" k2 :{NINES}");
    let ring = ring(Some(&primary), Some(&next))
        .expect("valid")
        .expect("a ring");
    assert_eq!(ring.primary_kid(), "k1", "the first configured");
    assert!(ring.resolve("k1").is_ok(), "k1");
    assert!(ring.resolve("k2").is_ok(), "k2, trimmed");
    let unknown = ring.resolve("k3").expect_err("not held");
    assert_eq!(
        unknown.code,
        PayloadCode::KeyUnknown,
        "an id this side does not hold"
    );
    assert!(
        format!("{ring:?}").contains("AesKey(..)"),
        "no key material in its Debug"
    );
}

#[test]
fn a_rotation_slot_alone_is_the_primary() {
    let next = format!("k2:{NINES}");
    let ring = ring(None, Some(&next)).expect("valid").expect("a ring");
    assert_eq!(ring.primary_kid(), "k2", "the only key");
}

#[test]
fn a_malformed_value_is_refused_by_its_variable_name() {
    let refused = [
        format!("k1{SEVENS}"),
        format!(":{SEVENS}"),
        format!("ecdh:{SEVENS}"),
        format!("{}:{SEVENS}", "k".repeat(33)),
        format!("k 1:{SEVENS}"),
        "k1:not base64!".to_owned(),
        "k1:BwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBw".to_owned(),
    ];
    for value in refused {
        let error = ring(Some(&value), None).expect_err("refused");
        assert_eq!(error, PayloadSetupError::Key("PAYLOAD_KEY"), "{value}");
    }
}

#[test]
fn two_variables_with_one_kid_are_refused() {
    let primary = format!("k1:{SEVENS}");
    let next = format!("k1:{NINES}");
    let error = ring(Some(&primary), Some(&next)).expect_err("duplicate");
    assert_eq!(
        error,
        PayloadSetupError::DuplicateKid("PAYLOAD_KEY_NEXT"),
        "names the second"
    );
}
