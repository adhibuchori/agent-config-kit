// The server's half of the payload contract, faked at the transport boundary for the session and
// middleware tests: its own P-256 key pair, the handshake, and the opening and sealing a backend
// does. The cipher underneath is the real one.
import CryptoKit
import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing

@testable import APIClient

/// Where the fake server lives.
let serverURL = URL(filePath: "/")

/// The time every exchange of these tests happens at.
let testNow: Int64 = 1_767_225_600_000

/// The x-payload-epk field.
let epkField = HTTPField.Name(PayloadEnvelope.epkHeader) ?? .accept

/// How often the handshake ran, and what the server last received.
actor ServerLog {
    /// The handshakes so far.
    private(set) var handshakes = 0
    /// The last request the server got, and its body as the server read it.
    private(set) var request: HTTPRequest?
    private(set) var body: Data?

    /// Counts one handshake.
    func handshake() {
        handshakes += 1
    }

    /// Keeps a request and its body.
    func received(_ request: HTTPRequest, _ body: Data?) {
        self.request = request
        self.body = body
    }
}

/// A transport that answers the handshake, and refuses anything else.
struct HandshakeTransport: ClientTransport {
    let status: Int
    let body: String
    let log: ServerLog

    func send(_ request: HTTPRequest, body _: HTTPBody?, baseURL _: URL, operationID _: String) async throws -> (
        HTTPResponse, HTTPBody?
    ) {
        await log.handshake()
        guard request.method == .get, request.headerFields[.cacheControl] == "no-store" else {
            throw PayloadError(.required, "not a handshake")
        }
        return plain(status, body, type: "application/json")
    }
}

/// A backend that holds a P-256 key pair.
struct PayloadTestServer: Sendable {
    /// The server's long-lived key pair.
    let privateKey = P256.KeyAgreement.PrivateKey()
    /// What it saw.
    let log = ServerLog()
    /// Its clock: the tests' fixed time, unless a test runs against the middleware's real clock.
    var clock = PayloadMiddleware.Clock.fixed(testNow)

    /// The public key the handshake serves.
    var publicKey: String {
        PayloadKeyAgreement.encoded(privateKey.publicKey)
    }

    /// A session whose handshake answers `status` with `body`, by default this server's key and
    /// mode `strict`.
    func session(status: Int = 200, body: String? = nil, honoursOff: Bool = true) -> PayloadSession {
        let answer = body ?? #"{"publicKey":"\#(publicKey)","mode":"strict"}"#
        let transport = HandshakeTransport(status: status, body: answer, log: log)
        let handshake = PayloadEndpoint(method: "GET", pattern: "/payload/handshake", policy: .none)
        return PayloadSession(serverURL: serverURL, transport: transport, handshake: handshake, honoursOff: honoursOff)
    }

    /// The key this server agrees with the app whose public key a request carries.
    func key(_ request: HTTPRequest) throws -> SymmetricKey {
        let epk = try #require(request.headerFields[epkField])
        return try PayloadKeyAgreement.key(privateKey, peer: epk)
    }

    /// The server's side of an exchange: it keeps what it got, opening a sealed request, then
    /// answers `json` with `status`, sealed when `seals` says so.
    func answer(_ json: String, status: Int, for endpoint: PayloadEndpoint, seals: Bool = true) -> PayloadNext {
        { request, body, _ in
            let now = clock.now
            var data: Data?
            if let body {
                data = try await Data(collecting: body, upTo: 1 << 20)
            }
            if let sealed = data, request.headerFields[.contentType] == PayloadEnvelope.mediaType {
                data = try PayloadCodec.open(sealed, key: key(request), now: now) { kid, timestamp in
                    PayloadEnvelope.requestAAD(
                        method: endpoint.method, pattern: endpoint.pattern, kid: kid, timestamp: timestamp)
                }
            }
            await log.received(request, data)
            guard seals else { return plain(status, json, type: "application/json") }
            let sealed = try PayloadCodec.seal(json: Data(json.utf8), key: key(request), now: now) { kid, timestamp in
                PayloadEnvelope.responseAAD(status: status, pattern: endpoint.pattern, kid: kid, timestamp: timestamp)
            }
            return respond(status, HTTPBody(sealed), type: PayloadEnvelope.mediaType)
        }
    }
}

/// A plaintext answer with a content type.
func plain(_ status: Int, _ body: String?, type: String = "application/problem+json") -> (HTTPResponse, HTTPBody?) {
    respond(status, body.map { HTTPBody($0) }, type: type)
}

/// An answer with a status, a body and a content type.
func respond(_ status: Int, _ body: HTTPBody?, type: String) -> (HTTPResponse, HTTPBody?) {
    var fields = HTTPFields()
    fields[.contentType] = type
    return (HTTPResponse(status: .init(code: status), headerFields: fields), body)
}

/// The bytes of a body.
func text(_ body: HTTPBody?) async throws -> String {
    try await String(collecting: try #require(body), upTo: 1 << 20)
}

/// The payload failure a call threw, or nil when it threw nothing or something else.
func payloadFailure<T>(_ work: () async throws -> T) async -> PayloadError? {
    do {
        _ = try await work()
        return nil
    } catch {
        return error as? PayloadError
    }
}
