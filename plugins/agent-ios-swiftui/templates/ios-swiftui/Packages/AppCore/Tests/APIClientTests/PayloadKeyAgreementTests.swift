// PayloadKeyAgreement beyond the shared vectors: the labels it uses, and keys that are no points.
// PayloadVectorsTests proves the agreement itself against the other implementations.
import CryptoKit
import Foundation
import Testing

@testable import APIClient

@Suite("PayloadKeyAgreement")
struct PayloadKeyAgreementTests {
    @Test("seals under the reserved kid, with the browser hop's HKDF label")
    func labels() {
        #expect(PayloadKeyAgreement.kid == "ecdh")
        #expect(PayloadKeyAgreement.info == "payload-envelope/v1/browser")
    }

    @Test("two sides agree one key, and a third side another")
    func agrees() throws {
        let app = P256.KeyAgreement.PrivateKey()
        let server = P256.KeyAgreement.PrivateKey()
        let ours = try PayloadKeyAgreement.key(app, peer: PayloadKeyAgreement.encoded(server.publicKey))
        let theirs = try PayloadKeyAgreement.key(server, peer: PayloadKeyAgreement.encoded(app.publicKey))
        let other = try PayloadKeyAgreement.key(
            P256.KeyAgreement.PrivateKey(), peer: PayloadKeyAgreement.encoded(app.publicKey))
        #expect(ours.withUnsafeBytes { Data($0) } == theirs.withUnsafeBytes { Data($0) })
        #expect(ours.withUnsafeBytes { Data($0) } != other.withUnsafeBytes { Data($0) })
        #expect(PayloadBase64URL.decode(PayloadKeyAgreement.encoded(app.publicKey))?.first == 0x04)
    }

    @Test("refuses a key that is not base64url or not a point", arguments: ["", "not base64", "BAEC"])
    func refuses(encoded: String) {
        #expect(throws: PayloadError(.malformed, "The peer public key is not a P-256 point")) {
            try PayloadKeyAgreement.publicKey(encoded)
        }
    }
}
