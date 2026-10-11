// The registry's types: every operation of the generated client is one entry with its pattern and
// its policy, keyed by the operation ID the client passes to its middlewares (AGENTS.md Rule 29).
// The entries themselves are generated: `node scripts/generate/payload-registry.mjs` writes
// PayloadEndpoints.generated.swift from the spec copy and payload.config.json, and
// `node scripts/check/payload-registry.mjs` fails when it is stale.

/// Which sides of an exchange are sealed. A half-policy names the side whose body cannot be sealed,
/// and is chosen by what the body needs, never by how sensitive it looks.
enum PayloadPolicy: Sendable {
    /// Both sides: the default for every operation.
    case strict
    /// Request plain, response sealed: a multipart upload, whose boundary must survive.
    case responseOnly
    /// Request sealed, response plain: an event stream, or a file the app saves or draws.
    case requestOnly
    /// Neither: the handshake, probes, a third party's webhook.
    case none

    /// Whether the request body is sealed.
    var sealsRequest: Bool {
        switch self {
        case .strict, .requestOnly:
            true
        case .responseOnly, .none:
            false
        }
    }

    /// Whether the response body is sealed.
    var sealsResponse: Bool {
        switch self {
        case .strict, .responseOnly:
            true
        case .requestOnly, .none:
            false
        }
    }
}

/// One registered operation: what both sides put in the AAD, and what is sealed.
struct PayloadEndpoint: Sendable {
    /// The HTTP method, uppercase.
    let method: String
    /// The route with `:param` placeholders, as the server's registry has it.
    let pattern: String
    /// What is sealed.
    let policy: PayloadPolicy
}

/// What the middleware and the session read: the operations, the handshake, and the switch.
struct PayloadRegistry: Sendable {
    #if DEBUG
        /// Whether a mode of `off` switches sealing off. Only a debug build honours it, so a Release
        /// build seals even when the server or the committed switch says `off` (AGENTS.md Rule 31).
        static let honoursOff = true
    #else
        static let honoursOff = false
    #endif

    /// The generated registry.
    static let generated = Self(
        entries: PayloadEndpoints.entries,
        handshake: PayloadEndpoints.handshake,
        switchedOff: PayloadEndpoints.configMode == "off"
    )

    /// Every operation of the generated client, by operation ID.
    let entries: [String: PayloadEndpoint]
    /// The handshake operation, `GET` with policy `none`; nil when the repo has none.
    let handshake: PayloadEndpoint?
    /// Whether the committed switch, `encryption` in payload.config.json, says `off`.
    let switchedOff: Bool
}
