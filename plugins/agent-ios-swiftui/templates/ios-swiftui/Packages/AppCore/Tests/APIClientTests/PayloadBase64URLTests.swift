// PayloadBase64URL: unpadded base64url out, and the lenient reading the other implementations share.
import Foundation
import Testing

@testable import APIClient

@Suite("PayloadBase64URL")
struct PayloadBase64URLTests {
    @Test("writes base64url without padding")
    func encodes() {
        #expect(PayloadBase64URL.encode(Data([0xFB, 0xFF, 0xBF])) == "-_-_")
        #expect(PayloadBase64URL.encode(Data([0xFF])) == "_w")
        #expect(PayloadBase64URL.encode(Data()).isEmpty)
    }

    @Test(
        "reads base64url, and standard base64 with padding and whitespace",
        arguments: [
            ("-_-_", [0xFB, 0xFF, 0xBF]), ("+/+/", [0xFB, 0xFF, 0xBF]), (" _w\n", [0xFF]), ("_w==", [0xFF]),
            ("/w==", [0xFF]),
        ] as [(String, [UInt8])]
    )
    func decodes(text: String, bytes: [UInt8]) {
        #expect(PayloadBase64URL.decode(text) == Data(bytes))
    }

    @Test("refuses what is not base64", arguments: ["a b", "a", "%%%%"])
    func refuses(text: String) {
        #expect(PayloadBase64URL.decode(text) == nil)
    }
}
