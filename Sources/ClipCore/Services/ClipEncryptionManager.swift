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
    /// Set when the key exists but couldn't be read this session (for example the Keychain prompt
    /// after an update was dismissed). The key is never replaced in that case: doing so would make
    /// every encrypted image and rich-text clip unreadable.
    private var keyUnavailable = false

    public enum EncryptionError: LocalizedError {
        case encryptionFailed
        case decryptionFailed
        case keyGenerationFailed
        case keyUnavailable

        public var errorDescription: String? {
            switch self {
            case .encryptionFailed:
                return "Failed to encrypt payload with AES-GCM."
            case .decryptionFailed:
                return "Failed to decrypt payload: authentication tag mismatch or corrupted ciphertext."
            case .keyGenerationFailed:
                return "Failed to generate or retrieve AES-256 symmetric key from Keychain."
            case .keyUnavailable:
                return "The clipboard encryption key in the Keychain couldn't be read."
            }
        }
    }

    public init() {}

    /// The AES-256 key, created on first use. Nil when the Keychain refused access this session;
    /// callers then store new payloads unencrypted instead of using a key that would orphan old ones.
    public var symmetricKey: SymmetricKey? {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cachedKey { return cached }
        if keyUnavailable { return nil }

        switch loadKeyFromKeychain() {
        case .found(let key):
            cachedKey = key
            return key
        case .failed:
            keyUnavailable = true
            return nil
        case .notFound:
            // First run: create the key. Only use it once it's saved, or later launches couldn't decrypt.
            let newKey = SymmetricKey(size: .bits256)
            guard saveKeyToKeychain(newKey) else {
                keyUnavailable = true
                return nil
            }
            cachedKey = newKey
            return newKey
        }
    }

    /// Encrypts raw data using AES-GCM (Nonce + Ciphertext + AuthTag combined)
    public func encrypt(data: Data) throws -> Data {
        guard let key = symmetricKey else { throw EncryptionError.keyUnavailable }
        let box = try AES.GCM.seal(data, using: key)
        guard let combined = box.combined else {
            throw EncryptionError.encryptionFailed
        }
        return combined
    }

    /// Decrypts AES-GCM sealed data, verifying authentication tag
    public func decrypt(data: Data) throws -> Data {
        guard let key = symmetricKey else { throw EncryptionError.keyUnavailable }
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key)
    }

    /// Safely attempts decryption; if data is unencrypted (legacy format), returns original data
    public func decryptSafely(data: Data) -> Data {
        if let decrypted = try? decrypt(data: data) {
            return decrypted
        }
        return data
    }

    // MARK: - macOS Keychain Integration (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`)

    private enum KeychainRead {
        case found(SymmetricKey)
        case notFound
        /// The item exists but couldn't be read (access denied, prompt dismissed, keychain locked…).
        case failed
    }

    private func loadKeyFromKeychain() -> KeychainRead {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let keyData = item as? Data, keyData.count == 32 else { return .failed }
            return .found(SymmetricKey(data: keyData))
        case errSecItemNotFound:
            return .notFound
        default:
            return .failed
        }
    }

    /// Adds the key. Never deletes an existing item: this only runs when none was found.
    private func saveKeyToKeychain(_ key: SymmetricKey) -> Bool {
        let keyData = key.withUnsafeBytes { Data($0) }
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }
}
