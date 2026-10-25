import Foundation
import CryptoKit
import Security

/// High-performance CryptoKit AES-GCM payload encryption service
/// Stores 256-bit symmetric encryption keys in the macOS Keychain with
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` to guarantee zero plaintext secret leakage to disk.
public final class ClipEncryptionManager: @unchecked Sendable {
    public static let shared = ClipEncryptionManager()

    private let serviceName = "com.notchkit.clipcore"
    private let accountName = "payload-encryption-key"
    private let lock = NSLock()
    private var cachedKey: SymmetricKey?

    public enum EncryptionError: LocalizedError {
        case encryptionFailed
        case decryptionFailed
        case keyGenerationFailed

        public var errorDescription: String? {
            switch self {
            case .encryptionFailed:
                return "Failed to encrypt payload with AES-GCM."
            case .decryptionFailed:
                return "Failed to decrypt payload: authentication tag mismatch or corrupted ciphertext."
            case .keyGenerationFailed:
                return "Failed to generate or retrieve AES-256 symmetric key from Keychain."
            }
        }
    }

    public init() {}

    /// Retrieves or provisions the 256-bit AES-GCM key from macOS Keychain
    public var symmetricKey: SymmetricKey {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cachedKey {
            return cached
        }

        if let keychainKey = loadKeyFromKeychain() {
            cachedKey = keychainKey
            return keychainKey
        }

        // Generate a new 256-bit cryptographic symmetric key
        let newKey = SymmetricKey(size: .bits256)
        saveKeyToKeychain(newKey)
        cachedKey = newKey
        return newKey
    }

    /// Encrypts raw data using AES-GCM (Nonce + Ciphertext + AuthTag combined)
    public func encrypt(data: Data) throws -> Data {
        let box = try AES.GCM.seal(data, using: symmetricKey)
        guard let combined = box.combined else {
            throw EncryptionError.encryptionFailed
        }
        return combined
    }

    /// Decrypts AES-GCM sealed data, verifying authentication tag
    public func decrypt(data: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: symmetricKey)
    }

    /// Safely attempts decryption; if data is unencrypted (legacy format), returns original data
    public func decryptSafely(data: Data) -> Data {
        if let decrypted = try? decrypt(data: data) {
            return decrypted
        }
        return data
    }

    // MARK: - macOS Keychain Integration (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`)

    private func loadKeyFromKeychain() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let keyData = item as? Data else {
            return nil
        }

        return SymmetricKey(data: keyData)
    }

    private func saveKeyToKeychain(_ key: SymmetricKey) {
        let keyData = key.withUnsafeBytes { Data($0) }

        // Delete existing item if present
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add with strict device-only post-unlock accessibility
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        _ = SecItemAdd(addQuery as CFDictionary, nil)
    }
}
