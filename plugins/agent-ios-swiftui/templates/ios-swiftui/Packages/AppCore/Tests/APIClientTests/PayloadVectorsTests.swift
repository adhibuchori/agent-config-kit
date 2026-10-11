// The shared vectors (AGENTS.md Rule 33): scripts/check/payload-vectors.json is the same file in
// every repo that speaks the payload contract, and this cipher, its AAD and its key agreement must
// agree with it byte for byte. Never regenerate the file to make a test pass: a mismatch means an
// implementation changed.
import CryptoKit
import Foundation
import Testing

@testable import APIClient

private func bytes(_ base64url: String) throws -> Data {
    try #require(PayloadBase64URL.decode(base64url))
}

/// The AAD this implementation builds for a vector.
private func aad(_ vector: PayloadVector) throws -> Data {
    if vector.kind == "request" {
        let method = try #require(vector.method)
        return PayloadEnvelope.requestAAD(
            method: method, pattern: vector.pattern, kid: vector.kid, timestamp: vector.timestamp)
    }
    let status = try #require(vector.status)
    return PayloadEnvelope.responseAAD(
        status: status, pattern: vector.pattern, kid: vector.kid, timestamp: vector.timestamp)
}

/// Opens a vector under a key with an AAD, and reads the plaintext as JSON.
private func open(_ vector: PayloadVector, key: SymmetricKey, aad: Data) throws -> JSONValue {
    let plaintext = try PayloadCipher.open(bytes(vector.sealed), nonce: bytes(vector.nonce), key: key, aad: aad)
    return try JSONDecoder().decode(JSONValue.self, from: plaintext)
}

@Suite("Payload vectors")
struct PayloadVectorsTests {
    @Test("builds every vector's AAD byte for byte, and opens it with the published key")
    func opensVectors() throws {
        let file = try payloadVectorFile()
        let key = SymmetricKey(data: try bytes(file.testBytes))
        #expect(!file.vectors.isEmpty)
        for vector in file.vectors + file.agreements.map(\.vector) {
            #expect(try aad(vector) == Data(vector.aad.utf8), "\(vector.aad)")
        }
        for vector in file.vectors {
            #expect(try open(vector, key: key, aad: aad(vector)) == vector.plaintext, "\(vector.aad)")
        }
    }

    @Test("refuses every vector under an AAD that names something else")
    func refusesRejects() throws {
        let file = try payloadVectorFile()
        let key = SymmetricKey(data: try bytes(file.testBytes))
        #expect(!file.rejects.isEmpty)
        for reject in file.rejects {
            let vector = try #require(file.vectors.first { $0.name == reject.vector })
            #expect(throws: PayloadError(.rejected, "Payload authentication failed"), "\(reject.name)") {
                try open(vector, key: key, aad: Data(reject.aad.utf8))
            }
        }
    }

    @Test("agrees the secret and the key from either side, and opens the agreed envelope")
    func agreesKeys() throws {
        let file = try payloadVectorFile()
        #expect(!file.agreements.isEmpty)
        for agreement in file.agreements {
            #expect(agreement.info == PayloadKeyAgreement.info)
            let jwk = try JSONDecoder().decode(ServerJWK.self, from: bytes(agreement.serverJwk))
            let server = try P256.KeyAgreement.PrivateKey(rawRepresentation: bytes(jwk.secret))
            let client = try P256.KeyAgreement.PrivateKey(rawRepresentation: bytes(agreement.clientPrivate))
            #expect(PayloadKeyAgreement.encoded(server.publicKey) == agreement.serverPublic)
            #expect(PayloadKeyAgreement.encoded(client.publicKey) == agreement.clientPublic)
            let fromServer = try PayloadKeyAgreement.secret(
                server, PayloadKeyAgreement.publicKey(agreement.clientPublic))
            let fromClient = try PayloadKeyAgreement.secret(
                client, PayloadKeyAgreement.publicKey(agreement.serverPublic))
            let secret = try bytes(agreement.sharedBytes)
            #expect(fromServer.withUnsafeBytes { Data($0) } == secret)
            #expect(fromClient.withUnsafeBytes { Data($0) } == secret)
            let key = try PayloadKeyAgreement.key(client, peer: agreement.serverPublic)
            let serverKey = try PayloadKeyAgreement.key(server, peer: agreement.clientPublic)
            let expected = try bytes(agreement.sessionBytes)
            #expect(key.withUnsafeBytes { Data($0) } == expected)
            #expect(serverKey.withUnsafeBytes { Data($0) } == expected)
            #expect(try open(agreement.vector, key: key, aad: aad(agreement.vector)) == agreement.vector.plaintext)
        }
    }

    @Test("refuses every point the contract refuses, with its code")
    func refusesPoints() throws {
        let file = try payloadVectorFile()
        #expect(!file.pointRejects.isEmpty)
        for reject in file.pointRejects {
            let code = try #require(PayloadCode(rawValue: reject.code))
            #expect(throws: PayloadError(code, "The peer public key is not a P-256 point"), "\(reject.name)") {
                try PayloadKeyAgreement.publicKey(reject.point)
            }
        }
    }
}
