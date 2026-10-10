use super::{Mode, resolve};
use crate::payload::setup::PayloadSetupError;

const FILE: &str = "payload.config.json encryption";

#[test]
fn the_committed_switch_decides_when_the_variable_is_unset_or_blank() {
    assert_eq!(resolve(None, "strict", true), Ok(Mode::Strict), "unset");
    assert_eq!(resolve(Some(" "), "off", false), Ok(Mode::Off), "blank");
}

#[test]
fn the_variable_wins_trimmed_and_in_any_case() {
    assert_eq!(
        resolve(Some(" Strict "), "off", true),
        Ok(Mode::Strict),
        "a deployment forces strict"
    );
    assert_eq!(
        resolve(Some("OFF"), "strict", false),
        Ok(Mode::Off),
        "a shell bisects locally"
    );
}

#[test]
fn a_typo_is_refused_and_never_read_as_strict() {
    assert_eq!(
        resolve(Some("stict"), "strict", false),
        Err(PayloadSetupError::Mode("PAYLOAD_MODE")),
        "env"
    );
    assert_eq!(
        resolve(None, "true", false),
        Err(PayloadSetupError::Mode(FILE)),
        "file"
    );
}

#[test]
fn off_is_refused_in_production_whichever_source_says_it() {
    let from_env = resolve(Some("off"), "strict", true);
    assert_eq!(
        from_env,
        Err(PayloadSetupError::OffInProduction("PAYLOAD_MODE")),
        "env"
    );
    let from_file = resolve(None, "off", true);
    assert_eq!(
        from_file,
        Err(PayloadSetupError::OffInProduction(FILE)),
        "file"
    );
}
