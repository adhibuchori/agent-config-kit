// PayloadMiddleware's answers against the fake server: what it opens, which plaintext it accepts,
// the refusals it throws, and when the session agrees a new key.
import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing

@testable import APIClient

private let getNote = PayloadEndpoint(method: "GET", pattern: "/notes/:id", policy: .strict)

private func get(_ session: PayloadSession, next: PayloadNext) async throws -> (
    HTTPResponse, HTTPBody?
) {
    let registry = PayloadRegistry(entries: ["getNote": getNote], handshake: nil, switchedOff: false)
    let middleware = PayloadMiddleware(session: session, registry: registry, honoursOff: true, clock: .fixed(testNow))
    let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/notes/n-1")
    return try await middleware.intercept(request, body: nil, baseURL: serverURL, operationID: "getNote", next: next)
}

/// A server that answers in plaintext.
private func plainly(_ status: Int, _ body: String?, type: String = "application/problem+json") -> PayloadNext {
    { _, _, _ in plain(status, body, type: type) }
}

@Suite("PayloadMiddleware answers")
struct PayloadMiddlewareResponseTests {
    @Test("opens a sealed problem under its own status, for the generated client to decode")
    func opensSealedProblem() async throws {
        let server = PayloadTestServer()
        let problem = #"{"code":"NOT_FOUND","status":404}"#
        let (response, body) = try await get(
            server.session(), next: server.answer(problem, status: 404, for: getNote))
        #expect(response.status.code == 404)
        #expect(response.headerFields[.contentType] == nil)
        #expect(try await text(body) == problem)
    }

    @Test("passes a plaintext problem on, and an empty answer")
    func passesPlainProblems() async throws {
        let server = PayloadTestServer()
        let problem = #"{"code":"NOT_FOUND","requestId":"r-1"}"#
        let (_, refused) = try await get(server.session(), next: plainly(404, problem))
        #expect(try await text(refused) == problem)
        let (_, empty) = try await get(server.session(), next: plainly(204, nil))
        #expect(try await text(empty).isEmpty)
        let (_, unparsed) = try await get(
            server.session(), next: plainly(502, "Bad gateway", type: "text/html"))
        #expect(try await text(unparsed) == "Bad gateway")
    }

    @Test("refuses a plaintext success on a sealed route as a downgrade")
    func refusesDowngrade() async {
        let server = PayloadTestServer()
        let failure = await payloadFailure {
            try await get(server.session(), next: plainly(200, #"{"id":"n-1"}"#, type: "application/json"))
        }
        #expect(failure?.code == .required)
    }

    @Test("throws the server's ENVELOPE_* refusal with its request id, and keeps the key unless it was rejected")
    func throwsRefusals() async {
        let server = PayloadTestServer()
        let session = server.session()
        let expired = await payloadFailure {
            try await get(session, next: plainly(400, #"{"code":"ENVELOPE_EXPIRED","requestId":"r-2"}"#))
        }
        #expect(
            expired == PayloadError(.expired, "The server refused the payload with ENVELOPE_EXPIRED", requestId: "r-2"))
        #expect(await server.log.handshakes == 1)
        let rejected = await payloadFailure {
            try await get(session, next: plainly(400, #"{"code":"ENVELOPE_REJECTED"}"#))
        }
        #expect(rejected?.code == .rejected)
        _ = try? await get(session, next: server.answer("{}", status: 200, for: getNote))
        #expect(await server.log.handshakes == 2)
    }

    @Test("drops the key when an answer fails to open, and refuses one with no envelope in it")
    func dropsKeyOnTag() async {
        let server = PayloadTestServer()
        let session = server.session()
        // Another server's key pair agrees another key with the same public key of this app.
        let foreign = await payloadFailure {
            try await get(session, next: PayloadTestServer().answer("{}", status: 200, for: getNote))
        }
        #expect(foreign?.code == .rejected)
        let empty = await payloadFailure {
            try await get(session, next: plainly(200, nil, type: PayloadEnvelope.mediaType))
        }
        #expect(empty?.code == .required)
        #expect(await server.log.handshakes == 2)
    }

    @Test("lets an error other than a payload failure through untouched")
    func otherErrors() async {
        let server = PayloadTestServer()
        let failure = await payloadFailure {
            try await get(server.session()) { _, _, _ in throw CancellationError() }
        }
        #expect(failure == nil)
    }
}
