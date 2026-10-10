// AppProblem through its public surface: decoding, the code it resolves, and what a screen shows.
import Foundation
import Testing

@testable import APIClient

private let base = AppProblem.typeBase

private func decode(_ json: String) throws -> AppProblem {
    try JSONDecoder().decode(AppProblem.self, from: Data(json.utf8))
}

@Suite("AppProblem")
struct AppProblemTests {
    @Test("decodes the members a screen uses, and skips the rest")
    func decodesWhatScreensUse() throws {
        let problem = try decode(
            #"{"type":"\#(base)NOT_FOUND","title":"Not found","status":404,"code":"NOT_FOUND","requestId":"r-1"}"#
        )
        #expect(problem == AppProblem(type: base + "NOT_FOUND", code: "NOT_FOUND", requestId: "r-1"))
    }

    @Test("ignores members of the wrong type instead of failing")
    func ignoresWrongTypes() throws {
        let problem = try decode(#"{"type":7,"title":[],"status":"404","code":"NOT_FOUND","requestId":{}}"#)
        #expect(problem == AppProblem(code: "NOT_FOUND"))
    }

    @Test("refuses a body that is not an object")
    func refusesNonObject() {
        #expect(throws: DecodingError.self) { try decode(#"["NOT_FOUND"]"#) }
    }

    @Test("round-trips through its encoding")
    func roundTrips() throws {
        let problem = AppProblem(type: base + "INTERNAL_ERROR", code: "INTERNAL_ERROR", requestId: "r-2")
        let data = try JSONEncoder().encode(problem)
        #expect(try JSONDecoder().decode(AppProblem.self, from: data) == problem)
    }

    @Test(
        "knows a code under this API's base, or with no type at all",
        arguments: [base + "NOT_FOUND", "about:blank", nil] as [String?]
    )
    func knowsCode(type: String?) {
        #expect(AppProblem(type: type, code: "NOT_FOUND").knownCode == .notFound)
    }

    @Test(
        "treats a foreign base, a mismatched tail or an unlisted code as unknown",
        arguments: [
            AppProblem(type: "https://other.invalid/problems/NOT_FOUND", code: "NOT_FOUND"),
            AppProblem(type: base + "INTERNAL_ERROR", code: "NOT_FOUND"),
            AppProblem(type: base + "RATE_LIMITED", code: "RATE_LIMITED"),
            AppProblem(type: base + "NOT_FOUND"),
        ]
    )
    func unknownCode(problem: AppProblem) {
        #expect(problem.knownCode == nil)
        #expect(problem.messageKey == "problem.unknown")
    }

    @Test("names the catalog key of a known code's message")
    func messageKeyOfKnownCode() {
        #expect(
            AppProblem(type: base + "VALIDATION_FAILED", code: "VALIDATION_FAILED").messageKey
                == "problem.VALIDATION_FAILED")
    }

    @Test(
        "builds the reference from the code and the start of the request id",
        arguments: [
            (AppProblem(code: "RATE_LIMITED", requestId: "0123456789abcdef"), "RATE_LIMITED · 01234567"),
            (AppProblem(code: "RATE_LIMITED", requestId: ""), "RATE_LIMITED"),
            (AppProblem(code: "RATE_LIMITED"), "RATE_LIMITED"),
            (AppProblem(requestId: "r-3"), "UNKNOWN · r-3"),
        ]
    )
    func reference(problem: AppProblem, expected: String) {
        #expect(problem.reference == expected)
    }

    @Test("lists every code once, each a SCREAMING_SNAKE_CASE identifier")
    func codesAreWellFormed() {
        let raw = ProblemCode.allCases.map(\.rawValue)
        #expect(Set(raw).count == raw.count)
        #expect(raw.allSatisfy { $0.wholeMatch(of: /[A-Z][A-Z0-9_]*/) != nil })
    }
}
