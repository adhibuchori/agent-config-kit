// PayloadCipher: a fresh nonce per seal, the tag appended, and one refusal for every way opening fails.
import CryptoKit
import Foundation
import Testing

@testable import APIClient

private let rejected = PayloadError(.rejected, "Payload authentication failed")

@Suite("PayloadCipher")
struct PayloadCipherTests {
    @Test("opens what it sealed, with a 12-byte nonce and a 16-byte tag")
    func roundTrips() throws {
        let key = SymmetricKey(size: .bits256)
        let aad = Data("1.POST./notes.ecdh.1".utf8)
        let first = try PayloadCipher.seal(Data("{}".utf8), key: key, aad: aad)
        let second = try PayloadCipher.seal(Data("{}".utf8), key: key, aad: aad)
        #expect(first.nonce.count == 12)
        #expect(first.sealed.count == 2 + 16)
        #expect(first.nonce != second.nonce)
        #expect(try PayloadCipher.open(first.sealed, nonce: first.nonce, key: key, aad: aad) == Data("{}".utf8))
    }

    @Test("refuses another key, another AAD, a changed byte and a nonce of another length")
    func refuses() throws {
        let key = SymmetricKey(size: .bits256)
        let aad = Data("1.POST./notes.ecdh.1".utf8)
        let (nonce, sealed) = try PayloadCipher.seal(Data("{}".utf8), key: key, aad: aad)
        var changed = sealed
        changed[changed.startIndex] ^= 1
        #expect(throws: rejected) {
            try PayloadCipher.open(sealed, nonce: nonce, key: SymmetricKey(size: .bits256), aad: aad)
        }
        #expect(throws: rejected) { try PayloadCipher.open(sealed, nonce: nonce, key: key, aad: Data("1.PUT".utf8)) }
        #expect(throws: rejected) { try PayloadCipher.open(changed, nonce: nonce, key: key, aad: aad) }
        #expect(throws: rejected) { try PayloadCipher.open(sealed, nonce: nonce + nonce, key: key, aad: aad) }
        #expect(throws: rejected) { try PayloadCipher.open(Data([1]), nonce: nonce, key: key, aad: aad) }
    }
}
