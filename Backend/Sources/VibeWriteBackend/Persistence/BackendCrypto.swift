import CryptoKit
import Foundation
import Vapor

enum BackendCryptoError: Error, LocalizedError {
    case missingSecretKey
    case emptySecretKey
    case invalidCiphertext

    var errorDescription: String? {
        switch self {
        case .missingSecretKey:
            return "Missing ADMIN_SECRET_ENCRYPTION_KEY."
        case .emptySecretKey:
            return "ADMIN_SECRET_ENCRYPTION_KEY must not be empty."
        case .invalidCiphertext:
            return "Encrypted secret data is invalid."
        }
    }
}

struct BackendSecretCipher: Sendable {
    private let key: SymmetricKey

    init(secretKey: String) throws {
        let trimmed = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BackendCryptoError.emptySecretKey
        }

        let digest = SHA256.hash(data: Data(trimmed.utf8))
        self.key = SymmetricKey(data: Data(digest))
    }

    static func resolveFromEnvironment() throws -> BackendSecretCipher {
        guard let secretKey = Environment.get("ADMIN_SECRET_ENCRYPTION_KEY") else {
            throw BackendCryptoError.missingSecretKey
        }

        return try BackendSecretCipher(secretKey: secretKey)
    }

    func encrypt<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(value)
        let sealedBox = try AES.GCM.seal(payload, using: key)
        guard let combined = sealedBox.combined else {
            throw BackendCryptoError.invalidCiphertext
        }

        return Data(combined).base64EncodedString()
    }

    func decrypt<T: Decodable>(_ ciphertext: String, as type: T.Type) throws -> T {
        guard let data = Data(base64Encoded: ciphertext) else {
            throw BackendCryptoError.invalidCiphertext
        }

        let sealedBox = try AES.GCM.SealedBox(combined: data)
        let payload = try AES.GCM.open(sealedBox, using: key)
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: payload)
    }

    func digest(_ value: String) -> String {
        let hash = SHA256.hash(data: Data(value.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
