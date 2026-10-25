import Foundation
import GRDB

public struct AppSettings: Codable, FetchableRecord, PersistableRecord, TableRecord, Identifiable, Sendable, Equatable {
    public static let databaseTableName = "app_settings"
    public static let primaryKeyId: Int64 = 1

    public var id: Int64
    /// Capacity limit (0 = Unlimited)
    public var maxHistory: Int
    /// Time-based retention in days (0 = Never auto-delete)
    public var retentionDays: Int
    public var isPaused: Bool
    public var ignoreConcealed: Bool
    /// Tool visibility toggles
    public var isSpeedMeterEnabled: Bool
    public var isClipboardEnabled: Bool
    public var isBatteryLimiterEnabled: Bool
    /// Battery charge threshold limit (e.g. 80%)
    public var batteryChargeLimit: Int

    public init(
        id: Int64 = primaryKeyId,
        maxHistory: Int = 1000,
        retentionDays: Int = 0,
        isPaused: Bool = false,
        ignoreConcealed: Bool = true,
        isSpeedMeterEnabled: Bool = true,
        isClipboardEnabled: Bool = true,
        isBatteryLimiterEnabled: Bool = true,
        batteryChargeLimit: Int = 80
    ) {
        self.id = id
        self.maxHistory = maxHistory
        self.retentionDays = retentionDays
        self.isPaused = isPaused
        self.ignoreConcealed = ignoreConcealed
        self.isSpeedMeterEnabled = isSpeedMeterEnabled
        self.isClipboardEnabled = isClipboardEnabled
        self.isBatteryLimiterEnabled = isBatteryLimiterEnabled
        self.batteryChargeLimit = batteryChargeLimit
    }

    public static let `default` = AppSettings()

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let maxHistory = Column(CodingKeys.maxHistory)
        public static let retentionDays = Column(CodingKeys.retentionDays)
        public static let isPaused = Column(CodingKeys.isPaused)
        public static let ignoreConcealed = Column(CodingKeys.ignoreConcealed)
        public static let isSpeedMeterEnabled = Column(CodingKeys.isSpeedMeterEnabled)
        public static let isClipboardEnabled = Column(CodingKeys.isClipboardEnabled)
        public static let isBatteryLimiterEnabled = Column(CodingKeys.isBatteryLimiterEnabled)
        public static let batteryChargeLimit = Column(CodingKeys.batteryChargeLimit)
    }
}
