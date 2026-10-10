// The only place this app seals and opens bodies (AGENTS.md Rules 29 and 30): a middleware of the
// generated client, last in its list so it runs innermost, next to the transport. Every other
// middleware, the generated decoding and the screens see plaintext.
import CryptoKit
import Foundation
import HTTPTypes
import OpenAPIRuntime

#if compiler(>=6.2)
    /// What a middleware calls to go on: the next middleware, or the transport. `@concurrent` as the
    /// runtime declares it, so it matches under `NonisolatedNonsendingByDefault` too.
    typealias PayloadNext =
        @concurrent @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
#else
    typealias PayloadNext = @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
#endif

/// Seals the request and opens the response of each registered operation, by its policy. Internal
/// like every payload type: the APIs of this target build it, with the session the app shares.
struct PayloadMiddleware: ClientMiddleware {
    private static let bodyBytes = 16 * 1024 * 1024
    private let session: PayloadSession
    private let registry: PayloadRegistry
    private let honoursOff: Bool
    private let clock: Clock

    /// The middleware for the generated registry, agreeing its key through `session`. Put it last in
    /// the client's `middlewares`.
    init(session: PayloadSession) {
        self.init(session: session, registry: .generated, honoursOff: PayloadRegistry.honoursOff, clock: .system)
    }

    /// A middleware with its registry, its build's rule for `off` and its clock given, for tests.
    init(session: PayloadSession, registry: PayloadRegistry, honoursOff: Bool, clock: Clock) {
        self.session = session
        self.registry = registry
        self.honoursOff = honoursOff
        self.clock = clock
    }

    /// Where the middleware reads the time: the system's clock, or a fixed instant for tests.
    enum Clock: Sendable {
        case system
        case fixed(Int64)

        /// The time in epoch milliseconds, as envelopes carry it.
        var now: Int64 {
            switch self {
            case .system:
                Int64(Date().timeIntervalSince1970 * 1000)
            case .fixed(let instant):
                instant
            }
        }
    }

    /// Refuses an operation the registry does not know, passes through one that seals nothing, and
    /// seals and opens the rest. A refusal or a failure is thrown as a `PayloadError`, which the
    /// client hands its caller as the underlying error of a `ClientError`.
    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: PayloadNext
    ) async throws -> (HTTPResponse, HTTPBody?) {
        guard let endpoint = registry.entries[operationID] else {
            throw PayloadError(.required, "\(operationID) is not in the payload registry; regenerate it")
        }
        let policy = endpoint.policy
        guard policy.sealsRequest || policy.sealsResponse, !(honoursOff && registry.switchedOff) else {
            return try await next(request, body, baseURL)
        }
        let agreement = try await session.agreement()
        guard agreement.sealing else { return try await next(request, body, baseURL) }
        let (sealedRequest, sealedBody) = try await seal(request, body, endpoint, agreement)
        let (response, responseBody) = try await next(sealedRequest, sealedBody, baseURL)
        do {
            return try await read(response, responseBody, endpoint, agreement)
        } catch let failure as PayloadError {
            if failure.code.dropsKey { await session.forget() }
            throw failure
        }
    }

    private func seal(
        _ request: HTTPRequest,
        _ body: HTTPBody?,
        _ endpoint: PayloadEndpoint,
        _ agreement: PayloadAgreement
    ) async throws -> (HTTPRequest, HTTPBody?) {
        var request = request
        // HTTPTypes names a field only through a failable initializer; this name is a valid token.
        if let name = HTTPField.Name(PayloadEnvelope.epkHeader) { request.headerFields[name] = agreement.epk }
        guard endpoint.policy.sealsRequest, let body else { return (request, body) }
        let plaintext = try await Data(collecting: body, upTo: Self.bodyBytes)
        let sealed = try PayloadCodec.seal(json: plaintext, key: agreement.key, now: clock.now) { kid, timestamp in
            PayloadEnvelope.requestAAD(
                method: endpoint.method, pattern: endpoint.pattern, kid: kid, timestamp: timestamp)
        }
        request.headerFields[.contentType] = PayloadEnvelope.mediaType
        request.headerFields[.contentLength] = nil
        return (request, HTTPBody(sealed))
    }

    private func read(
        _ response: HTTPResponse,
        _ body: HTTPBody?,
        _ endpoint: PayloadEndpoint,
        _ agreement: PayloadAgreement
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let sealed = response.headerFields[.contentType]?.hasPrefix(PayloadEnvelope.mediaType) == true
        if sealed, endpoint.policy.sealsResponse {
            let data = try await collect(body)
            return try open(response, data, endpoint, agreement)
        }
        switch response.status.kind {
        case .clientError, .serverError:
            // A plaintext answer is accepted as a refusal: an ENVELOPE_* one is thrown, any other
            // problem goes on to the generated client.
            let data = try await collect(body)
            if let refusal = Self.refusal(in: data) { throw refusal }
            return (response, HTTPBody(data))
        default:
            guard endpoint.policy.sealsResponse else { return (response, body) }
            // A plaintext success on a sealed route is a downgrade, whoever sent it.
            let data = try await collect(body)
            guard data.isEmpty else { throw PayloadError(.required, "\(endpoint.pattern) answered in plaintext") }
            return (response, HTTPBody(data))
        }
    }

    private func open(
        _ response: HTTPResponse,
        _ data: Data,
        _ endpoint: PayloadEndpoint,
        _ agreement: PayloadAgreement
    ) throws -> (HTTPResponse, HTTPBody?) {
        let status = response.status.code
        let plaintext = try PayloadCodec.open(data, key: agreement.key, now: clock.now) { kid, timestamp in
            PayloadEnvelope.responseAAD(status: status, pattern: endpoint.pattern, kid: kid, timestamp: timestamp)
        }
        // Without a content type the generated client decodes the first one the operation declares,
        // JSON or problem JSON alike.
        var response = response
        response.headerFields[.contentType] = nil
        response.headerFields[.contentLength] = nil
        return (response, HTTPBody(plaintext))
    }

    private func collect(_ body: HTTPBody?) async throws -> Data {
        guard let body else { return Data() }
        return try await Data(collecting: body, upTo: Self.bodyBytes)
    }

    private static func refusal(in data: Data) -> PayloadError? {
        guard let problem = try? JSONDecoder().decode(Refusal.self, from: data),
            let code = PayloadCode(rawValue: problem.code)
        else { return nil }
        return PayloadError(code, "The server refused the payload with \(problem.code)", requestId: problem.requestId)
    }
}

/// The members of a refusal this middleware reads: its code, and the request id support quotes.
private struct Refusal: Decodable {
    let code: String
    let requestId: String?
}
