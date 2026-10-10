// The wire format of the payload contract: what an envelope is, and what its ciphertext is bound
// to. Every constant here has a twin in each other implementation (.claude/PAYLOAD-CONTRACT.md
// § Wire format), and scripts/check/payload-vectors.json compares them (AGENTS.md Rule 33).
import Foundation

/// A sealed body as it travels, `{v, alg, kid, iv, ct, ts}`: one shape for requests and responses.
struct PayloadEnvelope: Codable, Equatable, Sendable {
    /// The media type of a sealed body, so a proxy or a log filter tells it from plaintext.
    static let mediaType = "application/vnd.payload-envelope+json"
    /// The header that carries this app's public key on every request of a sealed route.
    static let epkHeader = "x-payload-epk"
    /// How far apart two clocks may be, either way, in milliseconds.
    static let maxClockSkew: Int64 = 120_000
    private static let currentVersion = 1
    private static let cipher = "A256GCM"

    private enum CodingKeys: String, CodingKey {
        case version = "v"
        case algorithm = "alg"
        case kid
        case nonce = "iv"
        case sealed = "ct"
        case timestamp = "ts"
    }

    /// The format version; 1, and anything else is refused, never guessed at.
    let version: Int
    /// The one algorithm version 1 defines: AES-256-GCM.
    let algorithm: String
    /// The key that sealed it: `ecdh` for a key this app agreed with the server.
    let kid: String
    /// The 96-bit nonce, base64url.
    let nonce: String
    /// The ciphertext with its 16-byte tag appended, base64url.
    let sealed: String
    /// When it was sealed, in epoch milliseconds.
    let timestamp: Int64

    /// A version 1 envelope around a sealed body.
    init(kid: String, nonce: Data, sealed: Data, timestamp: Int64) {
        version = Self.currentVersion
        algorithm = Self.cipher
        self.kid = kid
        self.nonce = PayloadBase64URL.encode(nonce)
        self.sealed = PayloadBase64URL.encode(sealed)
        self.timestamp = timestamp
    }

    /// Reads an envelope out of a body. Anything else, an unknown version or a missing field
    /// included, is not an envelope this build reads: `ENVELOPE_REQUIRED`.
    init(parsing body: Data) throws {
        guard let read = try? JSONDecoder().decode(Self.self, from: body), read.version == Self.currentVersion,
            read.algorithm == Self.cipher
        else { throw PayloadError(.required, "Body is not a payload envelope") }
        self = read
    }

    /// The envelope as the body of a request.
    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// The authenticated data of a request, never sent: `1.<METHOD>.<pattern>.<kid>.<ts>`, with the
    /// registry's `:param` pattern, so an envelope opens only on the route and method it was
    /// sealed for.
    static func requestAAD(method: String, pattern: String, kid: String, timestamp: Int64) -> Data {
        Data("\(currentVersion).\(method.uppercased()).\(pattern).\(kid).\(timestamp)".utf8)
    }

    /// The authenticated data of a response: `1.<status>.<pattern>.<kid>.<ts>`, so a 200 body
    /// cannot be replayed as the body of a 403.
    static func responseAAD(status: Int, pattern: String, kid: String, timestamp: Int64) -> Data {
        Data("\(currentVersion).\(status).\(pattern).\(kid).\(timestamp)".utf8)
    }

    /// Whether a timestamp sits inside the window around `now`. A post-dated one is refused too.
    static func isFresh(_ timestamp: Int64, now: Int64) -> Bool {
        ((now - maxClockSkew)...(now + maxClockSkew)).contains(timestamp)
    }
}
