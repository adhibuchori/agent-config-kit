use super::{PayloadCode, PayloadError, WIRE_NAMES};
use crate::platform::error::{PROBLEM_TYPE_BASE, WireCode as _};

#[test]
fn every_code_has_the_wire_name_title_and_type_of_the_contract_table() {
    let table = [
        (
            PayloadCode::Required,
            "ENVELOPE_REQUIRED",
            "Sealed body required",
        ),
        (
            PayloadCode::Malformed,
            "ENVELOPE_MALFORMED",
            "Malformed envelope",
        ),
        (PayloadCode::Expired, "ENVELOPE_EXPIRED", "Envelope expired"),
        (
            PayloadCode::KeyUnknown,
            "ENVELOPE_KEY_UNKNOWN",
            "Unknown payload key",
        ),
        (
            PayloadCode::Rejected,
            "ENVELOPE_REJECTED",
            "Envelope rejected",
        ),
    ];
    assert_eq!(
        WIRE_NAMES.len(),
        table.len(),
        "the document lists every code"
    );
    for ((code, name, title), listed) in table.into_iter().zip(WIRE_NAMES) {
        assert_eq!(code.as_str(), name, "{code:?} on the wire");
        assert_eq!(listed, name, "{code:?} in the document, in order");
        assert_eq!(code.title(), title, "{code:?} title");
        assert_eq!(
            code.type_uri(),
            format!("{PROBLEM_TYPE_BASE}{name}"),
            "{code:?} type"
        );
    }
}

#[test]
fn an_error_displays_its_reason_and_keeps_its_code() {
    let error = PayloadError::new(PayloadCode::Expired, "outside the window");
    assert_eq!(
        error.to_string(),
        "outside the window",
        "the reason is for the log"
    );
    assert_eq!(error.code, PayloadCode::Expired, "the code is for the wire");
}
