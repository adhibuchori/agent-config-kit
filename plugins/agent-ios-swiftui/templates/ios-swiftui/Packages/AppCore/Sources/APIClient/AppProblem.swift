// A problem detail (RFC 9457) as this app reads it. The generated client decodes every
// `Problem` response into this type (typeOverrides in openapi-generator-config.yaml), so a code
// the backend adds after this build shipped still decodes: it becomes the generic message.
// AGENTS.md Rule 12 and .claude/rules/common/error-codes.md say how screens use it.

/// A problem detail body from the API. Each member is read on its own and a member of the wrong
/// type is ignored (RFC 9457 §3.1), so a malformed field never hides the code. Only what a screen
/// uses is read: `title` and `status` serve the server's logs, and `detail` never reaches a screen.
package struct AppProblem: Error, Codable, Hashable, Sendable {
    /// The API's problem-type base. `type` is this base plus the code, and it equals
    /// `x-problem-type-base` in the spec (`scripts/check/error-codes.sh` compares them). Changing it
    /// after a release turns every error in the installed apps into the generic message.
    package static let typeBase = "https://example.invalid/problems/"

    /// The problem type: `typeBase` plus the code. Absent means `about:blank`.
    package let type: String?
    /// The registered error code, such as `NOT_FOUND`.
    package let code: String?
    /// The request's id, shown in the reference of a problem this app does not know.
    package let requestId: String?

    /// A problem with the given members, for tests and previews.
    package init(type: String? = nil, code: String? = nil, requestId: String? = nil) {
        self.type = type
        self.code = code
        self.requestId = requestId
    }

    /// Decodes each member with `try?`, so a member with an unexpected type reads as absent.
    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try? container.decode(String.self, forKey: .type)
        code = try? container.decode(String.self, forKey: .code)
        requestId = try? container.decode(String.self, forKey: .requestId)
    }

    /// The code this app has a message for, or nil. A known code counts only when `type` is this
    /// API's base plus that code, or when `type` is absent or `about:blank` (an API that does not
    /// mint types yet). A known code under another base, or a `type` whose tail differs from
    /// `code`, is unknown.
    package var knownCode: ProblemCode? {
        guard let code, let known = ProblemCode(rawValue: code) else { return nil }
        switch type {
        case nil, "about:blank", Self.typeBase + code:
            return known
        default:
            return nil
        }
    }

    /// The String Catalog key of the message to show: `problem.<CODE>` for a known code, else
    /// `problem.unknown`, which is shown together with `reference`.
    package var messageKey: String {
        guard let knownCode else { return "problem.unknown" }
        return "problem.\(knownCode.rawValue)"
    }

    /// `CODE · <first 8 characters of the request id>`, the reference a person can quote to
    /// support. `UNKNOWN` stands in for a missing code.
    package var reference: String {
        let shown = code ?? "UNKNOWN"
        guard let requestId, !requestId.isEmpty else { return shown }
        return "\(shown) · \(requestId.prefix(8))"
    }
}

/// Every error code this app has a message for: the `Problem.code` enum of the backend's spec,
/// which `scripts/check/error-codes.sh` compares with these raw values. Screens switch over it with
/// no `default:`, so a case added here fails the build until every screen maps it.
package enum ProblemCode: String, CaseIterable, Sendable {
    /// The resource does not exist, or this caller may not know that it does.
    case notFound = "NOT_FOUND"
    /// The request body or a parameter failed validation.
    case validationFailed = "VALIDATION_FAILED"
    /// The server failed; the reference identifies the request.
    case internalError = "INTERNAL_ERROR"
}
