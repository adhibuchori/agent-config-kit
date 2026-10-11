use super::PayloadSetupError;

#[test]
fn every_refusal_names_what_to_fix_and_never_a_value() {
    let messages = [
        (
            PayloadSetupError::Mode("PAYLOAD_MODE"),
            "PAYLOAD_MODE must be",
        ),
        (
            PayloadSetupError::OffInProduction("PAYLOAD_MODE"),
            "refused in production",
        ),
        (
            PayloadSetupError::Key("PAYLOAD_KEY_NEXT"),
            "PAYLOAD_KEY_NEXT must be \"kid:base64key\"",
        ),
        (
            PayloadSetupError::DuplicateKid("PAYLOAD_KEY_NEXT"),
            "repeats the kid",
        ),
        (PayloadSetupError::ServerKey, "PAYLOAD_SERVER_JWK must be"),
        (
            PayloadSetupError::Registry("GET", "/api/a"),
            "GET /api/a is inconsistent; regenerate",
        ),
    ];
    for (error, expected) in messages {
        let message = error.to_string();
        assert!(message.contains(expected), "{message}");
    }
}
