// The one cipher on the wire: AES-256-GCM through CryptoKit, a 12-byte nonce fresh for every seal
// and the 16-byte tag appended to the ciphertext (.claude/PAYLOAD-CONTRACT.md § Wire format). The
// additional authenticated data is never sent: it is mixed into the tag, so a ciphertext lifted
// from one route fails to open on another.
import CryptoKit
import Foundation

/// AES-256-GCM sealing and opening in the layout every implementation shares.
enum PayloadCipher {
    /// 96 bits, the nonce length GCM is specified for; any other length is refused.
    static let nonceBytes = 12

    /// Encrypts bytes under a key, bound to the AAD, with a fresh nonce. Returns the nonce and the
    /// ciphertext with the tag appended.
    static func seal(_ plaintext: Data, key: SymmetricKey, aad: Data) throws -> (nonce: Data, sealed: Data) {
        let box = try AES.GCM.seal(plaintext, using: key, nonce: AES.GCM.Nonce(), authenticating: aad)
        return (Data(box.nonce), box.ciphertext + box.tag)
    }

    /// Verifies and decrypts. One failure, `ENVELOPE_REJECTED`, for a wrong key, a tampered body,
    /// a foreign AAD and a bad nonce alike: saying which one failed tells a prober which half of a
    /// guess was right.
    static func open(_ sealed: Data, nonce: Data, key: SymmetricKey, aad: Data) throws -> Data {
        guard nonce.count == nonceBytes, let box = try? AES.GCM.SealedBox(combined: nonce + sealed),
            let plaintext = try? AES.GCM.open(box, using: key, authenticating: aad)
        else { throw PayloadError(.rejected, "Payload authentication failed") }
        return plaintext
    }
}
