// The one error mapper of the APIClient's calls (AGENTS.md Rules 12 and 32): whatever a call of the
// generated client throws reaches the screens as an AppProblem, and a payload failure as the
// problem of its ENVELOPE_* code, the same one a refusal from the server names.
import OpenAPIRuntime

extension AppProblem {
    /// The problem behind an error a call of the generated client threw. An `AppProblem` stays as it
    /// is. A payload failure, which the client hands over inside a `ClientError`, becomes the problem
    /// of its `ENVELOPE_*` code under this API's base, so `knownCode` resolves it like a problem the
    /// server sent. Anything else, a lost connection say, is the unknown problem.
    package init(failure: any Error) {
        switch (failure as? ClientError)?.underlyingError ?? failure {
        case let problem as AppProblem:
            self = problem
        case let payload as PayloadError:
            let code = payload.code.rawValue
            self.init(type: Self.typeBase + code, code: code, requestId: payload.requestId)
        default:
            self.init()
        }
    }
}
