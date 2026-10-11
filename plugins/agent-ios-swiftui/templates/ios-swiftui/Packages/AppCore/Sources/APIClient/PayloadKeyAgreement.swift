// Key agreement for this app's hop. An app bundle is readable, so it holds no payload secret
// (AGENTS.md Rules 28 and 31): the server keeps a long-lived P-256 key pair, this app mints an
// ephemeral one per session, and both derive the same AES-256 key without sending it. The app's
// public key rides in x-payload-epk on every request, so the server stores nothing.
//
// This hides nothing from the person holding the device, who can read the key from memory. It
// buys integrity and resistance to passive capture: .claude/PAYLOAD-CONTRACT.md § Threat model.
import CryptoKit
import Foundation

/// ECDH on P-256, then HKDF-SHA-256 with an empty salt and the browser hop's label.
enum PayloadKeyAgreement {
    /// The `kid` of an envelope sealed under an agreed key; never a pre-shared key's id.
    static let kid = "ecdh"
    /// The HKDF label. A native app is a public client on the browser's hop, so it reuses the
    /// browser's label: one wire format, and a new label needs envelope version 2.
    static let info = "payload-envelope/v1/browser"
    private static let pointBytes = 65
    private static let uncompressed: UInt8 = 0x04

    /// A peer's public key from its base64url 65-byte uncompressed point, `04‖X‖Y`. Anything else,
    /// a point off the curve or a compressed one included, is `ENVELOPE_MALFORMED`: validating the
    /// point is what makes an invalid-curve attack fail here.
    static func publicKey(_ encoded: String) throws -> P256.KeyAgreement.PublicKey {
        guard let point = PayloadBase64URL.decode(encoded), point.count == pointBytes, point.first == uncompressed,
            let key = try? P256.KeyAgreement.PublicKey(x963Representation: point)
        else { throw PayloadError(.malformed, "The peer public key is not a P-256 point") }
        return key
    }

    /// A public key as the header and the handshake carry it: its uncompressed point, base64url.
    static func encoded(_ publicKey: P256.KeyAgreement.PublicKey) -> String {
        PayloadBase64URL.encode(publicKey.x963Representation)
    }

    /// The ECDH secret, the x-coordinate of the shared point.
    static func secret(_ privateKey: P256.KeyAgreement.PrivateKey, _ peer: P256.KeyAgreement.PublicKey) throws
        -> SharedSecret
    {
        try privateKey.sharedSecretFromKeyAgreement(with: peer)
    }

    /// The AES-256-GCM key of a secret. The raw secret is a curve coordinate, not uniformly random,
    /// so it goes through HKDF first; the empty salt is RFC 5869's choice when none is shared.
    static func key(_ secret: SharedSecret) -> SymmetricKey {
        secret.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: Data(), sharedInfo: Data(info.utf8), outputByteCount: 32)
    }

    /// The key this side's private key agrees with a peer's base64url public point.
    static func key(_ privateKey: P256.KeyAgreement.PrivateKey, peer: String) throws -> SymmetricKey {
        try key(secret(privateKey, publicKey(peer)))
    }
}
