// scripts/check/payload-vectors.json as PayloadVectorsTests reads it: the shapes of its sections,
// and JSON compared by meaning. The file is shared by every implementation of the payload contract.
import Foundation

/// The vector file, read through this file's path, so the package needs no resource.
func payloadVectorFile() throws -> PayloadVectorFile {
    var url = URL(filePath: #filePath)
    for _ in 1...5 {
        url.deleteLastPathComponent()
    }
    let data = try Data(contentsOf: url.appending(path: "scripts/check/payload-vectors.json"))
    return try JSONDecoder().decode(PayloadVectorFile.self, from: data)
}

/// The sections every implementation proves itself against.
struct PayloadVectorFile: Decodable {
    /// The published AES-256 key of `vectors`, base64url.
    let testBytes: String
    let vectors: [PayloadVector]
    let rejects: [VectorReject]
    let agreements: [VectorAgreement]
    let pointRejects: [VectorPointReject]
}

/// One sealed body with what it is bound to.
struct PayloadVector: Decodable {
    enum CodingKeys: String, CodingKey {
        case name, kind, method, status, pattern, kid, plaintext, aad
        case timestamp = "ts"
        case nonce = "iv"
        case sealed = "ct"
    }

    let name: String?
    let kind: String
    let method: String?
    let status: Int?
    let pattern: String
    let kid: String
    let plaintext: JSONValue
    let timestamp: Int64
    let aad: String
    let nonce: String
    let sealed: String
}

/// A vector under an AAD that names something else.
struct VectorReject: Decodable {
    let name: String
    let vector: String
    let aad: String
}

/// A key agreement between a server key pair and an app's, with what both derive.
struct VectorAgreement: Decodable {
    let info: String
    let serverJwk: String
    let serverPublic: String
    let clientPrivate: String
    let clientPublic: String
    let sharedBytes: String
    let sessionBytes: String
    let vector: PayloadVector
}

/// A public key the contract refuses, with its code.
struct VectorPointReject: Decodable {
    let name: String
    let point: String
    let code: String
}

/// The private half of `PAYLOAD_SERVER_JWK`.
struct ServerJWK: Decodable {
    enum CodingKeys: String, CodingKey {
        case secret = "d"
    }

    let secret: String
}

/// Any JSON value, compared by meaning rather than by bytes.
enum JSONValue: Decodable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }
}
