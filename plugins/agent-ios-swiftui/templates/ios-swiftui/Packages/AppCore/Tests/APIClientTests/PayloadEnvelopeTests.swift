// PayloadEnvelope: the shape it reads and writes, the AAD it binds, and the freshness window.
import Foundation
import Testing

@testable import APIClient

private func envelope(_ json: String) throws -> PayloadEnvelope {
    try PayloadEnvelope(parsing: Data(json.utf8))
}

@Suite("PayloadEnvelope")
struct PayloadEnvelopeTests {
    @Test("writes version 1 with every field, and reads it back")
    func roundTrips() throws {
        let sealed = PayloadEnvelope(kid: "ecdh", nonce: Data([1, 2, 3]), sealed: Data([255]), timestamp: 42)
        #expect(sealed.version == 1)
        #expect(sealed.algorithm == "A256GCM")
        #expect(sealed.nonce == "AQID")
        #expect(sealed.sealed == "_w")
        #expect(try PayloadEnvelope(parsing: sealed.encoded()) == sealed)
        let keys = try JSONDecoder().decode([String: JSONScalar].self, from: sealed.encoded()).keys
        #expect(Set(keys) == ["v", "alg", "kid", "iv", "ct", "ts"])
    }

    @Test(
        "refuses a body that is not an envelope this build reads",
        arguments: [
            #"{"v":2,"alg":"A256GCM","kid":"ecdh","iv":"AA","ct":"AA","ts":1}"#,
            #"{"v":1,"alg":"A128GCM","kid":"ecdh","iv":"AA","ct":"AA","ts":1}"#,
            #"{"v":1,"alg":"A256GCM","kid":"ecdh","iv":"AA","ts":1}"#,
            #"{"v":1,"alg":"A256GCM","kid":"ecdh","iv":"AA","ct":"AA","ts":"1"}"#,
            #"{"title":"plaintext"}"#,
            "not json",
        ]
    )
    func refusesOthers(json: String) {
        #expect(throws: PayloadError(.required, "Body is not a payload envelope")) { try envelope(json) }
    }

    @Test("binds a request to its method, upper-cased, its pattern, its key and its time")
    func requestAAD() {
        let aad = PayloadEnvelope.requestAAD(method: "post", pattern: "/notes/:id", kid: "ecdh", timestamp: 7)
        #expect(aad == Data("1.POST./notes/:id.ecdh.7".utf8))
    }

    @Test("binds a response to its status, its pattern, its key and its time")
    func responseAAD() {
        let aad = PayloadEnvelope.responseAAD(status: 201, pattern: "/notes/:id", kid: "ecdh", timestamp: 7)
        #expect(aad == Data("1.201./notes/:id.ecdh.7".utf8))
    }

    @Test(
        "accepts a timestamp up to two minutes away, either way, and nothing further",
        arguments: [(0, true), (120_000, true), (-120_000, true), (120_001, false), (-120_001, false)]
            as [(Int64, Bool)]
    )
    func freshness(offset: Int64, fresh: Bool) {
        #expect(PayloadEnvelope.isFresh(1_000_000 + offset, now: 1_000_000) == fresh)
    }

    @Test("names its media type and its key header as the contract does")
    func names() {
        #expect(PayloadEnvelope.mediaType == "application/vnd.payload-envelope+json")
        #expect(PayloadEnvelope.epkHeader == "x-payload-epk")
    }
}

/// One JSON scalar: enough to read an envelope's keys.
private enum JSONScalar: Decodable {
    case text(String)
    case number(Int64)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int64.self) {
            self = .number(value)
        } else {
            self = .text(try container.decode(String.self))
        }
    }
}
