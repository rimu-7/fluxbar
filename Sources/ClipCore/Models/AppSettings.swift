import Foundation
import GRDB

public struct AppSettings: Codable, FetchableRecord, PersistableRecord, TableRecord, Identifiable, Sendable, Equatable {
    public static let databaseTableName = "app_settings"
    public static let primaryKeyId: Int64 = 1

    public var id: Int64
    public var maxHistory: Int
    public var isPaused: Bool
    public var ignoreConcealed: Bool

    public init(
        id: Int64 = primaryKeyId,
        maxHistory: Int = 250,
        isPaused: Bool = false,
        ignoreConcealed: Bool = true
    ) {
        self.id = id
        self.maxHistory = maxHistory
        self.isPaused = isPaused
        self.ignoreConcealed = ignoreConcealed
    }

    public static let `default` = AppSettings()

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let maxHistory = Column(CodingKeys.maxHistory)
        public static let isPaused = Column(CodingKeys.isPaused)
        public static let ignoreConcealed = Column(CodingKeys.ignoreConcealed)
    }
}
