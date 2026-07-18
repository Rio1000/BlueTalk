import Foundation
import CryptoKit

struct CryptoManager {

    /// Derives a per-peer symmetric key from the local private key and the
    /// peer's public key via X25519 ECDH + HKDF-SHA256.
    static func deriveKey(
        localPrivate: Curve25519.KeyAgreement.PrivateKey,
        remotePublic: Curve25519.KeyAgreement.PublicKey
    ) -> SymmetricKey? {
        guard let shared = try? localPrivate.sharedSecretFromKeyAgreement(with: remotePublic) else {
            return nil
        }
        return shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: "BlueTalk-v1".data(using: .utf8)!,
            sharedInfo: Data(),
            outputByteCount: 32
        )
    }

    static func encrypt(data: Data, using key: SymmetricKey) -> Data? {
        guard let sealedBox = try? AES.GCM.seal(data, using: key) else { return nil }
        return sealedBox.combined
    }

    static func decrypt(combined: Data, using key: SymmetricKey) -> Data? {
        guard let sealedBox = try? AES.GCM.SealedBox(combined: combined),
              let plaintext = try? AES.GCM.open(sealedBox, using: key) else { return nil }
        return plaintext
    }

    /// Generates a fresh X25519 key pair for key exchange.
    static func generateKeyPair() -> Curve25519.KeyAgreement.PrivateKey {
        Curve25519.KeyAgreement.PrivateKey()
    }

    /// Exports the public key as raw bytes for transmission in the hello frame.
    static func exportPublicKey(_ privateKey: Curve25519.KeyAgreement.PrivateKey) -> Data {
        privateKey.publicKey.rawRepresentation
    }

    /// Imports a peer's public key from raw bytes received in their hello frame.
    static func importPublicKey(_ data: Data) -> Curve25519.KeyAgreement.PublicKey? {
        try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: data)
    }
}
