// PayloadSession against a handshake at the transport boundary: one handshake per session, a
// failed one forgotten, the answers it refuses, and `off` honoured only where a build allows it.
import CryptoKit
import Foundation
import Testing

@testable import APIClient

@Suite("PayloadSession")
struct PayloadSessionTests {
    @Test("agrees the server's key once, however many requests ask together")
    func agreesOnce() async throws {
        let server = PayloadTestServer()
        let session = server.session()
        async let first = session.agreement()
        async let second = session.agreement()
        let (one, two) = try await (first, second)
        #expect(one.epk == two.epk)
        #expect(one.sealing)
        #expect(await server.log.handshakes == 1)
        let serverKey = try PayloadKeyAgreement.key(server.privateKey, peer: one.epk)
        #expect(serverKey.withUnsafeBytes { Data($0) } == one.key.withUnsafeBytes { Data($0) })
    }

    @Test("agrees a new key after forget, with a new key pair of its own")
    func forgets() async throws {
        let server = PayloadTestServer()
        let session = server.session()
        let before = try await session.agreement()
        await session.forget()
        let after = try await session.agreement()
        #expect(before.epk != after.epk)
        #expect(await server.log.handshakes == 2)
    }

    @Test("forgets a failed handshake, so the next request tries again")
    func forgetsFailure() async {
        let server = PayloadTestServer()
        let session = server.session(status: 503, body: "{}")
        #expect(await payloadFailure { try await session.agreement() }?.code == .keyUnknown)
        #expect(await payloadFailure { try await session.agreement() }?.code == .keyUnknown)
        #expect(await server.log.handshakes == 2)
    }

    @Test(
        "refuses an answer with no usable public key",
        arguments: [
            (#"{"mode":"strict"}"#, PayloadCode.keyUnknown),
            (#"{"publicKey":""}"#, .keyUnknown),
            (#"{"publicKey":7}"#, .keyUnknown),
            ("not json", .keyUnknown),
            (#"{"publicKey":"not a point"}"#, .malformed),
            (#"{"publicKey":"BAEC"}"#, .malformed),
        ]
    )
    func refusesAnswers(body: String, code: PayloadCode) async {
        let session = PayloadTestServer().session(body: body)
        #expect(await payloadFailure { try await session.agreement() }?.code == code)
    }

    @Test("has no key to agree when the registry names no handshake")
    func noHandshake() async {
        let transport = HandshakeTransport(status: 200, body: "{}", log: ServerLog())
        let session = PayloadSession(serverURL: serverURL, transport: transport, handshake: nil, honoursOff: true)
        #expect(await payloadFailure { try await session.agreement() }?.code == .keyUnknown)
    }

    @Test("honours a handshake's off only when the build does", arguments: [true, false])
    func modeOff(honoursOff: Bool) async throws {
        let server = PayloadTestServer()
        let body = #"{"publicKey":"\#(server.publicKey)","mode":"off"}"#
        let agreement = try await server.session(body: body, honoursOff: honoursOff).agreement()
        #expect(agreement.sealing == !honoursOff)
    }

    @Test("builds from the generated registry, with its own uncached transport or a given one")
    func packageInitialisers() {
        let transport = HandshakeTransport(status: 200, body: "{}", log: ServerLog())
        _ = PayloadSession(serverURL: serverURL)
        _ = PayloadSession(serverURL: serverURL, transport: transport)
        #expect(PayloadRegistry.honoursOff)
    }
}
