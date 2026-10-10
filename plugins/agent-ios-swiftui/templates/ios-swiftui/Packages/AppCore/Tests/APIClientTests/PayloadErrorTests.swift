// PayloadCode and PayloadError: the five wire codes, and the one that drops the agreed key.
import Testing

@testable import APIClient

@Suite("PayloadError")
struct PayloadErrorTests {
    @Test("lists the contract's five codes, as the wire writes them")
    func codes() {
        #expect(
            PayloadCode.allCases.map(\.rawValue) == [
                "ENVELOPE_REQUIRED", "ENVELOPE_MALFORMED", "ENVELOPE_EXPIRED", "ENVELOPE_KEY_UNKNOWN",
                "ENVELOPE_REJECTED",
            ])
    }

    @Test("drops the agreed key only for a tag that failed", arguments: PayloadCode.allCases)
    func dropsKey(code: PayloadCode) {
        #expect(code.dropsKey == (code == .rejected))
    }

    @Test("keeps a refusal's request id, and has none of its own")
    func requestId() {
        #expect(PayloadError(.expired, "late", requestId: "r-1").requestId == "r-1")
        #expect(PayloadError(.expired, "late").requestId == nil)
    }
}
