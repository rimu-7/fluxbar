import Foundation
import CryptoKit

/// Externalized Media Sandbox managing large image and payload blobs outside of SQLite
public final class ClipBlobManager: @unchecked Sendable {
    public static let shared = ClipBlobManager()

    public static let blobThresholdBytes: Int = 100 * 1024 // 100 KB threshold

    public let blobsDirectoryURL: URL
    private let fileManager = FileManager.default

    public init(customDirectoryURL: URL? = nil) {
        if let custom = customDirectoryURL {
            self.blobsDirectoryURL = custom
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.blobsDirectoryURL = appSupport.appendingPathComponent("NotchKit/Blobs", isDirectory: true)
        }
        createDirectoryIfNeeded()
    }

    private func createDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: blobsDirectoryURL.path) {
            try? fileManager.createDirectory(at: blobsDirectoryURL, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o700 // Restricted to owner only
            ])
        }
    }

    /// Computes SHA-256 content address for arbitrary binary data
    public static func computeHash(data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Stores a payload if it exceeds threshold, returning `blob://<hash>` reference, or nil if <= threshold
    public func storeBlobIfExceedsThreshold(data: Data) -> String? {
        guard data.count > Self.blobThresholdBytes else {
            return nil
        }
        return storeBlob(data: data)
    }

    /// Stores data with SHA-256 content addressing, returning `blob://<hash>` reference
    public func storeBlob(data: Data) -> String {
        createDirectoryIfNeeded()
        let hash = Self.computeHash(data: data)
        let fileURL = blobsDirectoryURL.appendingPathComponent("\(hash).bin")

        if !fileManager.fileExists(atPath: fileURL.path) {
            try? data.write(to: fileURL, options: .atomic)
        }

        return "blob://\(hash)"
    }

    /// Retrieves data from `blob://<hash>` reference or raw hash
    public func retrieveBlob(reference: String) -> Data? {
        let hash: String
        if reference.hasPrefix("blob://") {
            hash = String(reference.dropFirst(7))
        } else {
            hash = reference
        }

        let fileURL = blobsDirectoryURL.appendingPathComponent("\(hash).bin")
        return try? Data(contentsOf: fileURL)
    }

    /// Deletes a blob given its reference
    public func deleteBlob(reference: String) {
        let hash = reference.hasPrefix("blob://") ? String(reference.dropFirst(7)) : reference
        let fileURL = blobsDirectoryURL.appendingPathComponent("\(hash).bin")
        try? fileManager.removeItem(at: fileURL)
    }

    /// Total size in bytes of all externalized blobs
    public var totalBlobsSizeBytes: Int64 {
        guard let files = try? fileManager.contentsOfDirectory(at: blobsDirectoryURL, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for file in files {
            if let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
