// A JSON body into an envelope and back: the one place that decides the order of operations. The
// AAD arrives as a builder because it holds the timestamp, and the timestamp is minted here.
import CryptoKit
import Foundation

/// Sealing and opening of JSON bodies.
enum PayloadCodec {
    /// Seals a JSON body under a key, as the bytes of an envelope. A body that is not JSON is
    /// refused before anything is sent (`ENVELOPE_MALFORMED`): a multipart upload or a file belongs
    /// on a route exempted as `response-only`.
    static func seal(
        json body: Data,
        key: SymmetricKey,
        now: Int64,
        aad: (_ kid: String, _ timestamp: Int64) -> Data
    ) throws -> Data {
        guard isJSON(body) else { throw PayloadError(.malformed, "A sealed body must be JSON") }
        let kid = PayloadKeyAgreement.kid
        let (nonce, sealed) = try PayloadCipher.seal(body, key: key, aad: aad(kid, now))
        return try PayloadEnvelope(kid: kid, nonce: nonce, sealed: sealed, timestamp: now).encoded()
    }

    /// Opens the bytes of an envelope back to its JSON. Freshness goes first, so a replay costs a
    /// subtraction rather than a GCM pass; then the tag, then the plaintext must be JSON.
    static func open(
        _ body: Data,
        key: SymmetricKey,
        now: Int64,
        aad: (_ kid: String, _ timestamp: Int64) -> Data
    ) throws -> Data {
        let envelope = try PayloadEnvelope(parsing: body)
        guard PayloadEnvelope.isFresh(envelope.timestamp, now: now) else {
            throw PayloadError(.expired, "Payload envelope is outside the freshness window")
        }
        guard let nonce = PayloadBase64URL.decode(envelope.nonce), let sealed = PayloadBase64URL.decode(envelope.sealed)
        else { throw PayloadError(.rejected, "Payload authentication failed") }
        let plaintext = try PayloadCipher.open(
            sealed, nonce: nonce, key: key, aad: aad(envelope.kid, envelope.timestamp))
        guard isJSON(plaintext) else { throw PayloadError(.malformed, "Decrypted payload is not JSON") }
        return plaintext
    }

    /// Whether bytes are one JSON value; a bare `null`, string or number counts.
    static func isJSON(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) != nil
    }
}
