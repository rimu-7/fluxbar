import Foundation
import GRDB

/// Common presentation interface implemented by both lightweight `ClipListSummary` and full `ClipItem`
public protocol ClipPresentable: Identifiable, Sendable {
    var id: Int64? { get }
    var stableId: Int64 { get }
    var previewText: String { get }
    var formatType: String { get }
    var sourceAppBundleId: String? { get }
    var sourceAppName: String? { get }
    var isPinned: Bool { get }
    var copyCount: Int { get }
    var charCount: Int { get }
    var lineCount: Int { get }
    var createdAt: Date { get }
    var updatedAt: Date { get }
    var thumbnailFilename: String? { get }
    var fileURL: String? { get }

    var isCodeSnippet: Bool { get }
    var isDocument: Bool { get }
    var isFile: Bool { get }
    var relativeTimeText: String { get }
}

/// Ultra-lightweight metadata-only projection for high-speed SwiftUI list rendering (~200 bytes per row)
/// Prevents loading heavy full text, rich RTF binaries, or raw images into memory.
public struct ClipListSummary: Codable, FetchableRecord, PersistableRecord, TableRecord, ClipPresentable, Equatable, Hashable {
    public static let databaseTableName = "clip_items"

    public let id: Int64?
    public let previewText: String
    public let formatType: String
    public let sourceAppBundleId: String?
    public let sourceAppName: String?
    public let isPinned: Bool
    public let copyCount: Int
    public let charCount: Int
    public let lineCount: Int
    public let createdAt: Date
    public let updatedAt: Date
    public let thumbnailFilename: String?
    public let fileURL: String?

    public init(
        id: Int64?,
        previewText: String,
        formatType: String = "text",
        sourceAppBundleId: String? = nil,
        sourceAppName: String? = nil,
        isPinned: Bool = false,
        copyCount: Int = 1,
        charCount: Int = 0,
        lineCount: Int = 1,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        thumbnailFilename: String? = nil,
        fileURL: String? = nil
    ) {
        self.id = id
        self.previewText = previewText
        self.formatType = formatType
        self.sourceAppBundleId = sourceAppBundleId
        self.sourceAppName = sourceAppName
        self.isPinned = isPinned
        self.copyCount = copyCount
        self.charCount = charCount
        self.lineCount = lineCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.thumbnailFilename = thumbnailFilename
        self.fileURL = fileURL
    }

    public var stableId: Int64 {
        id ?? Int64(bitPattern: UInt64(previewText.hashValue))
    }

    public var isCodeSnippet: Bool {
        formatType == "code"
    }

    public var isDocument: Bool {
        formatType == "doc" || formatType == "rtf"
    }

    public var isFile: Bool {
        formatType == "file" || fileURL != nil
    }

    public var relativeTimeText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: updatedAt, relativeTo: Date())
    }
}
