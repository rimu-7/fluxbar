import Foundation
import CryptoKit
import GRDB

public struct ClipItem: Codable, FetchableRecord, PersistableRecord, TableRecord, Identifiable, Sendable, Equatable, Hashable {
    public static let databaseTableName = "clip_items"

    public var id: Int64?
    public var content: String
    public var contentHash: String
    public var charCount: Int
    public var lineCount: Int
    public var sourceAppBundleId: String?
    public var sourceAppName: String?
    public var copyCount: Int
    public var isPinned: Bool
    public var formatType: String
    public var rtfData: Data?
    public var htmlContent: String?
    public var fileURL: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: Int64? = nil,
        content: String,
        contentHash: String? = nil,
        charCount: Int? = nil,
        lineCount: Int? = nil,
        sourceAppBundleId: String? = nil,
        sourceAppName: String? = nil,
        copyCount: Int = 1,
        isPinned: Bool = false,
        formatType: String = "text",
        rtfData: Data? = nil,
        htmlContent: String? = nil,
        fileURL: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.contentHash = contentHash ?? Self.computeHash(for: content)
        self.charCount = charCount ?? content.count
        self.lineCount = lineCount ?? Self.computeLineCount(for: content)
        self.sourceAppBundleId = sourceAppBundleId
        self.sourceAppName = sourceAppName
        self.copyCount = copyCount
        self.isPinned = isPinned
        self.formatType = formatType
        self.rtfData = rtfData
        self.htmlContent = htmlContent
        self.fileURL = fileURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func computeHash(for content: String) -> String {
        let digest = SHA256.hash(data: Data(content.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func computeLineCount(for content: String) -> Int {
        if content.isEmpty { return 0 }
        var count = 1
        for scalar in content.unicodeScalars {
            if scalar == "\n" {
                count += 1
            }
        }
        return count
    }

    public var isCodeSnippet: Bool {
        if formatType == "code" { return true }
        // Heuristic detection based on multiple lines, typical code characters/keywords
        if lineCount > 1 {
            let codeIndicators = ["{", "}", "func ", "def ", "class ", "import ", "const ", "let ", "var ", "return ", "if (", "=>", "://", "</", "/>", "SELECT ", "CREATE "]
            for indicator in codeIndicators {
                if content.contains(indicator) {
                    return true
                }
            }
            if content.hasPrefix("    ") || content.hasPrefix("\t") {
                return true
            }
        }
        return false
    }

    public var isDocument: Bool {
        formatType == "doc" || formatType == "rtf" || rtfData != nil
    }

    public var isFile: Bool {
        formatType == "file" || fileURL != nil
    }

    public var previewText: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "(empty)" }
        let lines = trimmed.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if lines.isEmpty { return trimmed }
        return lines.prefix(3).joined(separator: "\n")
    }

    public var relativeTimeText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: updatedAt, relativeTo: Date())
    }

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let content = Column(CodingKeys.content)
        public static let contentHash = Column(CodingKeys.contentHash)
        public static let charCount = Column(CodingKeys.charCount)
        public static let lineCount = Column(CodingKeys.lineCount)
        public static let sourceAppBundleId = Column(CodingKeys.sourceAppBundleId)
        public static let sourceAppName = Column(CodingKeys.sourceAppName)
        public static let copyCount = Column(CodingKeys.copyCount)
        public static let isPinned = Column(CodingKeys.isPinned)
        public static let formatType = Column(CodingKeys.formatType)
        public static let rtfData = Column(CodingKeys.rtfData)
        public static let htmlContent = Column(CodingKeys.htmlContent)
        public static let fileURL = Column(CodingKeys.fileURL)
        public static let createdAt = Column(CodingKeys.createdAt)
        public static let updatedAt = Column(CodingKeys.updatedAt)
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
