// PayloadCodec: JSON in, an envelope out, and the order in which opening refuses.
import CryptoKit
import Foundation
import Testing

@testable import APIClient

private let key = SymmetricKey(size: .bits256)

private func aad(_ kid: String, _ timestamp: Int64) -> Data {
    PayloadEnvelope.requestAAD(method: "POST", pattern: "/notes", kid: kid, timestamp: timestamp)
}

private func open(_ body: Data, now: Int64 = testNow) throws -> Data {
    try PayloadCodec.open(body, key: key, now: now, aad: aad)
}

/// An envelope around `plaintext`, sealed without the codec's JSON check.
private func envelope(of plaintext: String, nonce: String? = nil) throws -> Data {
    let (sealedNonce, sealed) = try PayloadCipher.seal(Data(plaintext.utf8), key: key, aad: aad("ecdh", testNow))
    let built = PayloadEnvelope(kid: "ecdh", nonce: sealedNonce, sealed: sealed, timestamp: testNow)
    let json = try #require(String(bytes: built.encoded(), encoding: .utf8))
    guard let nonce else { return Data(json.utf8) }
    return Data(json.replacingOccurrences(of: built.nonce, with: nonce).utf8)
}

@Suite("PayloadCodec")
struct PayloadCodecTests {
    @Test("opens what it sealed, under the kid of an agreed key", arguments: [#"{"title":"Groceries"}"#, "null", "7"])
    func roundTrips(json: String) throws {
        let sealed = try PayloadCodec.seal(json: Data(json.utf8), key: key, now: testNow, aad: aad)
        #expect(try PayloadEnvelope(parsing: sealed).kid == "ecdh")
        #expect(try open(sealed) == Data(json.utf8))
    }

    @Test("refuses to seal a body that is not JSON", arguments: ["", "--boundary", "{"])
    func refusesNonJSON(body: String) {
        #expect(throws: PayloadError(.malformed, "A sealed body must be JSON")) {
            try PayloadCodec.seal(json: Data(body.utf8), key: key, now: testNow, aad: aad)
        }
    }

    @Test("refuses an expired envelope before it runs the cipher")
    func refusesExpired() throws {
        let sealed = try envelope(of: "{}", nonce: "not base64")
        #expect(throws: PayloadError(.expired, "Payload envelope is outside the freshness window")) {
            try open(sealed, now: testNow + 120_001)
        }
    }

    @Test("refuses a field that is not base64url as a failed tag")
    func refusesBadField() throws {
        #expect(throws: PayloadError(.rejected, "Payload authentication failed")) {
            try open(envelope(of: "{}", nonce: "not base64"))
        }
    }

    @Test("refuses an opened plaintext that is not JSON")
    func refusesPlaintext() throws {
        #expect(throws: PayloadError(.malformed, "Decrypted payload is not JSON")) {
            try open(envelope(of: "plain text"))
        }
    }

    @Test("refuses a body that is no envelope")
    func refusesPlainBody() {
        #expect(throws: PayloadError(.required, "Body is not a payload envelope")) { try open(Data("{}".utf8)) }
    }
}
