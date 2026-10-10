// PayloadMiddleware's requests against the fake server: which operations it seals, which it lets
// pass, and the envelope a server opens. Its answers are in PayloadMiddlewareResponseTests.
import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing

@testable import APIClient

private let createNote = PayloadEndpoint(method: "POST", pattern: "/notes/:id", policy: .strict)

private func middleware(
    _ server: PayloadTestServer,
    _ policy: PayloadPolicy,
    session: PayloadSession? = nil,
    switchedOff: Bool = false
) -> PayloadMiddleware {
    let endpoint = PayloadEndpoint(method: createNote.method, pattern: createNote.pattern, policy: policy)
    let registry = PayloadRegistry(entries: ["createNote": endpoint], handshake: nil, switchedOff: switchedOff)
    return PayloadMiddleware(
        session: session ?? server.session(), registry: registry, honoursOff: true, clock: .fixed(testNow))
}

private func post(_ middleware: PayloadMiddleware, _ body: String?, next: PayloadNext) async throws -> (
    HTTPResponse, HTTPBody?
) {
    var request = HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/notes/n-1")
    request.headerFields[.contentType] = "application/json"
    return try await middleware.intercept(
        request, body: body.map { HTTPBody($0) }, baseURL: serverURL, operationID: "createNote", next: next)
}

@Suite("PayloadMiddleware requests")
struct PayloadMiddlewareTests {
    @Test("seals a strict request, opens its answer, and hands the client plain JSON")
    func sealsStrict() async throws {
        let server = PayloadTestServer()
        let next = server.answer(#"{"id":"n-1"}"#, status: 201, for: createNote)
        let (response, body) = try await post(middleware(server, .strict), #"{"title":"Groceries"}"#, next: next)
        #expect(try await text(body) == #"{"id":"n-1"}"#)
        #expect(response.headerFields[.contentType] == nil)
        let sent = try #require(await server.log.request)
        #expect(sent.headerFields[.contentType] == PayloadEnvelope.mediaType)
        #expect(try #require(await server.log.body) == Data(#"{"title":"Groceries"}"#.utf8))
    }

    @Test("sends the public key without a body, and seals nothing it has not got")
    func keyWithoutBody() async throws {
        let server = PayloadTestServer()
        let (_, body) = try await post(
            middleware(server, .strict), nil, next: server.answer("[]", status: 200, for: createNote))
        #expect(try await text(body) == "[]")
        let sent = try #require(await server.log.request)
        #expect(sent.headerFields[epkField] != nil)
        #expect(sent.headerFields[.contentType] == "application/json")
    }

    @Test("request-only: seals the request and passes the plain answer through")
    func requestOnly() async throws {
        let server = PayloadTestServer()
        let next = server.answer("data: 1", status: 200, for: createNote, seals: false)
        let (_, body) = try await post(middleware(server, .requestOnly), #"{"title":"x"}"#, next: next)
        #expect(try await text(body) == "data: 1")
        #expect(try #require(await server.log.body) == Data(#"{"title":"x"}"#.utf8))
    }

    @Test("response-only: sends the body plain with the key, and opens the answer")
    func responseOnly() async throws {
        let server = PayloadTestServer()
        let next = server.answer(#"{"ok":true}"#, status: 200, for: createNote)
        let (_, body) = try await post(middleware(server, .responseOnly), "--boundary", next: next)
        #expect(try await text(body) == #"{"ok":true}"#)
        #expect(try #require(await server.log.body) == Data("--boundary".utf8))
        #expect(try #require(await server.log.request).headerFields[epkField] != nil)
    }

    @Test("refuses a body that is not JSON on a sealed request, before sending it")
    func refusesNonJSON() async {
        let server = PayloadTestServer()
        let failure = await payloadFailure {
            try await post(
                middleware(server, .strict), "--boundary", next: server.answer("{}", status: 200, for: createNote))
        }
        #expect(failure?.code == .malformed)
        #expect(await server.log.request == nil)
    }

    @Test("refuses an operation the registry does not know")
    func refusesUnregistered() async {
        let server = PayloadTestServer()
        let failure = await payloadFailure {
            try await middleware(server, .strict).intercept(
                HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/elsewhere"), body: nil,
                baseURL: serverURL, operationID: "elsewhere", next: server.answer("{}", status: 200, for: createNote))
        }
        #expect(failure?.code == .required)
        #expect(await server.log.handshakes == 0)
    }

    @Test(
        "passes plaintext through, with no handshake, when nothing is sealed or a debug build is switched off",
        arguments: [(PayloadPolicy.none, false), (.strict, true)]
    )
    func passesThrough(policy: PayloadPolicy, switchedOff: Bool) async throws {
        let server = PayloadTestServer()
        let next = server.answer(#"{"id":"n-1"}"#, status: 201, for: createNote, seals: false)
        let (_, body) = try await post(middleware(server, policy, switchedOff: switchedOff), "{}", next: next)
        #expect(try await text(body) == #"{"id":"n-1"}"#)
        #expect(await server.log.handshakes == 0)
        #expect(try #require(await server.log.request).headerFields[epkField] == nil)
    }

    @Test("passes plaintext through when a debug build's handshake says off")
    func handshakeOff() async throws {
        let server = PayloadTestServer()
        let session = server.session(body: #"{"publicKey":"\#(server.publicKey)","mode":"off"}"#)
        let next = server.answer(#"{"id":"n-1"}"#, status: 201, for: createNote, seals: false)
        let (_, body) = try await post(middleware(server, .strict, session: session), "{}", next: next)
        #expect(try await text(body) == #"{"id":"n-1"}"#)
        #expect(try #require(await server.log.request).headerFields[epkField] == nil)
    }

    @Test("builds from the generated registry, and tells the time in epoch milliseconds")
    func generated() async {
        let server = PayloadTestServer()
        let failure = await payloadFailure {
            try await PayloadMiddleware(session: server.session()).intercept(
                HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/"), body: nil, baseURL: serverURL,
                operationID: "an operation no spec has", next: server.answer("{}", status: 200, for: createNote))
        }
        #expect(failure?.code == .required)
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        #expect(abs(PayloadMiddleware.Clock.system.now - now) < 60_000)
    }
}
