use super::{from_base64url, to_base64url};

#[test]
fn bytes_travel_as_unpadded_base64url() {
    let bytes = [0xfb, 0xff, 0xbf, 0x00];
    assert_eq!(
        to_base64url(&bytes),
        "-_-_AA",
        "url-safe alphabet, no padding"
    );
    assert_eq!(from_base64url("-_-_AA"), Some(bytes.to_vec()), "and back");
}

#[test]
fn standard_base64_with_padding_and_whitespace_is_read_too() {
    let read = from_base64url("  +/+/AA==\n");
    assert_eq!(
        read,
        Some(vec![0xfb, 0xff, 0xbf, 0x00]),
        "as a person pastes it"
    );
}

#[test]
fn text_that_is_not_base64_is_refused() {
    assert_eq!(from_base64url("not base64!"), None, "a space and a bang");
    assert_eq!(from_base64url("A"), None, "one character is no byte");
}
