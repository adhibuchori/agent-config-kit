// Bytes as an envelope and the x-payload-epk header carry them: unpadded base64url, the encoding
// every implementation of the payload contract writes (.claude/PAYLOAD-CONTRACT.md § Wire format).
import Foundation

/// Base64url without padding, and the lenient reading the other implementations share.
enum PayloadBase64URL {
    /// Encodes bytes as unpadded base64url.
    static func encode(_ bytes: Data) -> String {
        bytes.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Decodes base64url, and standard base64 with padding and surrounding whitespace as a person
    /// pastes it. Nil for anything else.
    static func decode(_ text: String) -> Data? {
        var standard = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while standard.hasSuffix("=") {
            standard.removeLast()
        }
        let padding = String(repeating: "=", count: (4 - standard.count % 4) % 4)
        return Data(base64Encoded: standard + padding)
    }
}
