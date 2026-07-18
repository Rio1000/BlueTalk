import Foundation
import CryptoKit

struct CryptoManager {
    // A shared 256-bit key. In a full implementation, you would generate this
    // via Diffie-Hellman key exchange when a new peer connects.
    static let symmetricKey = SymmetricKey(data: SHA256.hash(data: "BlueTalkSharedSecretKey123!".data(using: .utf8)!))

    static func encrypt(text: String) -> String {
        guard let data = text.data(using: .utf8),
              let sealedBox = try? AES.GCM.seal(data, using: symmetricKey) else {
            return text
        }
        // Returns a base64 string combining the ciphertext and authentication tag
        return sealedBox.combined?.base64EncodedString() ?? text
    }

    static func decrypt(base64String: String) -> String {
        guard let data = Data(base64Encoded: base64String),
              let sealedBox = try? AES.GCM.SealedBox(combined: data),
              let decryptedData = try? AES.GCM.open(sealedBox, using: symmetricKey) else {
            // Fallback to plain text if it wasn't encrypted (allows backward compatibility)
            return base64String
        }
        return String(data: decryptedData, encoding: .utf8) ?? base64String
    }
}
