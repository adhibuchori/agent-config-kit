// AppProblem(failure:), the one error mapper: what a screen gets for whatever a call threw.
import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing

@testable import APIClient

/// The error the client throws when a middleware failed: the failure inside a ClientError.
private func clientError(_ underlying: any Error) -> ClientError {
    ClientError(
        operationID: "getNote", operationInput: "", request: nil, requestBody: nil, baseURL: nil, response: nil,
        responseBody: nil, causeDescription: "Middleware failed", underlyingError: underlying)
}

@Suite("AppProblem(failure:)")
struct PayloadProblemTests {
    @Test("gives a payload failure the problem of its code under this API's base", arguments: PayloadCode.allCases)
    func payloadFailures(code: PayloadCode) {
        let failure = PayloadError(code, "for the log", requestId: "r-1")
        let expected = AppProblem(type: AppProblem.typeBase + code.rawValue, code: code.rawValue, requestId: "r-1")
        #expect(AppProblem(failure: clientError(failure)) == expected)
        #expect(AppProblem(failure: failure) == expected)
    }

    @Test("keeps a problem the call threw, wrapped or not")
    func keepsProblems() {
        let problem = AppProblem(type: AppProblem.typeBase + "NOT_FOUND", code: "NOT_FOUND", requestId: "r-2")
        #expect(AppProblem(failure: problem) == problem)
        #expect(AppProblem(failure: clientError(problem)) == problem)
    }

    @Test("makes anything else the unknown problem")
    func unknown() {
        #expect(AppProblem(failure: CancellationError()) == AppProblem())
        #expect(AppProblem(failure: clientError(URLError(.notConnectedToInternet))) == AppProblem())
    }
}
