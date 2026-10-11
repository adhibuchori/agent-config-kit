// This app's half of the payload handshake (.claude/PAYLOAD-CONTRACT.md § Hops): one key
// agreed per session from `GET` on the registry's handshake, held in memory only and never in the
// Keychain, and never pinned: the server may rotate its key pair, and an installed app follows by
// agreeing again (AGENTS.md Rule 31).
import CryptoKit
import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

/// The key this app agreed with the server, and the public key that names it to the server.
struct PayloadAgreement: Sendable {
    /// The AES-256-GCM key.
    let key: SymmetricKey
    /// This app's public key, base64url, for the x-payload-epk header.
    let epk: String
    /// False only when a debug build met a server whose handshake said `off`.
    let sealing: Bool
}

/// The session's agreed key, shared by every API the app builds for one server. Requests that
/// arrive together share one handshake; a failed one is forgotten, so a request made offline does
/// not fail every later one.
package actor PayloadSession {
    private static let handshakeBytes = 64 * 1024
    /// The transport the clients send through; the handshake uses it too, past the middlewares.
    let transport: any ClientTransport
    private let serverURL: URL
    private let handshake: PayloadEndpoint?
    private let honoursOff: Bool
    private var negotiation: Task<PayloadAgreement, any Error>?

    /// A session with the server at `serverURL`, sending through a URLSession that keeps no cache:
    /// a sealed answer is bound to one session's key, and URLCache does not honour `Vary`.
    package init(serverURL: URL) {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        self.init(serverURL: serverURL, transport: URLSessionTransport(configuration: .init(session: session)))
    }

    /// A session with the server at `serverURL` through `transport`, whose URLSession keeps no cache.
    package init(serverURL: URL, transport: any ClientTransport) {
        let handshake = PayloadRegistry.generated.handshake
        self.init(
            serverURL: serverURL, transport: transport, handshake: handshake, honoursOff: PayloadRegistry.honoursOff)
    }

    /// A session with its handshake operation and its build's rule for `off` given, for tests.
    init(serverURL: URL, transport: any ClientTransport, handshake: PayloadEndpoint?, honoursOff: Bool) {
        self.serverURL = serverURL
        self.transport = transport
        self.handshake = handshake
        self.honoursOff = honoursOff
    }

    /// The agreed key, negotiated on first use.
    func agreement() async throws -> PayloadAgreement {
        let task: Task<PayloadAgreement, any Error>
        if let negotiation {
            task = negotiation
        } else {
            task = Task { try await negotiate() }
            negotiation = task
        }
        do {
            return try await task.value
        } catch {
            if negotiation == task { negotiation = nil }
            throw error
        }
    }

    /// Drops the agreed key, so the next request agrees a new one.
    func forget() {
        negotiation = nil
    }

    private func negotiate() async throws -> PayloadAgreement {
        guard let handshake else { throw PayloadError(.keyUnknown, "The registry names no payload handshake") }
        var request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: handshake.pattern)
        request.headerFields[.accept] = "application/json"
        request.headerFields[.cacheControl] = "no-store"
        let (response, body) = try await transport.send(
            request, body: nil, baseURL: serverURL, operationID: "payloadHandshake")
        guard response.status == .ok, let body else {
            throw PayloadError(.keyUnknown, "The payload handshake answered \(response.status.code)")
        }
        let data = try await Data(collecting: body, upTo: Self.handshakeBytes)
        guard let answer = try? JSONDecoder().decode(HandshakeAnswer.self, from: data), !answer.publicKey.isEmpty else {
            throw PayloadError(.keyUnknown, "The payload handshake returned no public key")
        }
        let ephemeral = P256.KeyAgreement.PrivateKey()
        let key = try PayloadKeyAgreement.key(ephemeral, peer: answer.publicKey)
        let epk = PayloadKeyAgreement.encoded(ephemeral.publicKey)
        return PayloadAgreement(key: key, epk: epk, sealing: answer.mode != "off" || !honoursOff)
    }
}

/// The handshake's answer, `{publicKey, mode}`. A mode other than `off`, or none, means strict, so a
/// server too old to say still gets envelopes.
private struct HandshakeAnswer: Decodable {
    let publicKey: String
    let mode: String?
}
