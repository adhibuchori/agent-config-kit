// The closed set of ways a sealed exchange fails, as this app sees it (.claude/PAYLOAD-CONTRACT.md
// § Refusals and error codes). The code crosses the wire and reaches the screens; the message is for
// logs only.

/// Every payload failure, by its wire code. The backend's spec lists the same five codes once it
/// seals bodies, so `ProblemCode` has a case for each (`scripts/check/error-codes.sh`) and every
/// screen maps them in its one switch over `AppProblem.knownCode` (AGENTS.md Rule 32).
enum PayloadCode: String, CaseIterable, Sendable {
    /// A sealed route answered in plaintext, or with a body that is not an envelope this build
    /// reads; also an operation the registry does not know, which this app refuses to send.
    case required = "ENVELOPE_REQUIRED"
    /// The exchange cannot complete: a body or an opened plaintext that is not JSON, or a key that
    /// is not a P-256 point.
    case malformed = "ENVELOPE_MALFORMED"
    /// Outside the freshness window: a replay, or two clocks that drifted apart.
    case expired = "ENVELOPE_EXPIRED"
    /// No key to agree on: the handshake failed, or the server holds no key pair.
    case keyUnknown = "ENVELOPE_KEY_UNKNOWN"
    /// The tag did not verify: tampering, the wrong key, or an envelope bound to another route.
    case rejected = "ENVELOPE_REJECTED"

    /// Whether the session drops its agreed key. Only a tag that failed says the key itself is
    /// wrong (the server restarted with a new key pair, say), so the next call agrees a new one
    /// instead of failing until the app restarts.
    var dropsKey: Bool {
        switch self {
        case .rejected:
            true
        case .required, .malformed, .expired, .keyUnknown:
            false
        }
    }
}

/// A payload failure: the code for the wire and the screens, the message for logs.
struct PayloadError: Error, Equatable, Sendable {
    /// What failed.
    let code: PayloadCode
    /// Why, for a log line. Never shown to a person and never sent.
    let message: String
    /// The server's request id, when the failure is a refusal the server sent.
    let requestId: String?

    /// A failure with its code, its log message and, for a server's refusal, its request id.
    init(_ code: PayloadCode, _ message: String, requestId: String? = nil) {
        self.code = code
        self.message = message
        self.requestId = requestId
    }
}
