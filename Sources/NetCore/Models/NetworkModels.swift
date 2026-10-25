import Foundation

/// Represents instantaneous download and upload transfer rates.
public struct NetworkSpeed: Sendable, Equatable {
    public let bytesInPerSec: UInt64
    public let bytesOutPerSec: UInt64
    public let timestamp: Date

    public init(bytesInPerSec: UInt64 = 0, bytesOutPerSec: UInt64 = 0, timestamp: Date = Date()) {
        self.bytesInPerSec = bytesInPerSec
        self.bytesOutPerSec = bytesOutPerSec
        self.timestamp = timestamp
    }

    public var formattedDownload: String {
        Self.formatRate(bytesInPerSec)
    }

    public var formattedUpload: String {
        Self.formatRate(bytesOutPerSec)
    }

    /// Menu bar string representation, e.g. "↓ 0 B/s  ↑ 1.02 KB/s"
    public var menuBarLabel: String {
        "↓ \(formattedDownload)  ↑ \(formattedUpload)"
    }

    public static func formatRate(_ bytesPerSec: UInt64) -> String {
        if bytesPerSec < 1024 {
            return "\(bytesPerSec) B/s"
        } else if bytesPerSec < 1024 * 1024 {
            let kb = Double(bytesPerSec) / 1024.0
            return String(format: "%.2f KB/s", kb)
        } else if bytesPerSec < 1024 * 1024 * 1024 {
            let mb = Double(bytesPerSec) / (1024.0 * 1024.0)
            return String(format: "%.2f MB/s", mb)
        } else {
            let gb = Double(bytesPerSec) / (1024.0 * 1024.0 * 1024.0)
            return String(format: "%.2f GB/s", gb)
        }
    }

    public static func formatBytes(_ bytes: UInt64) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            let kb = Double(bytes) / 1024.0
            return String(format: "%.1f KB", kb)
        } else if bytes < 1024 * 1024 * 1024 {
            let mb = Double(bytes) / (1024.0 * 1024.0)
            return String(format: "%.2f MB", mb)
        } else {
            let gb = Double(bytes) / (1024.0 * 1024.0 * 1024.0)
            return String(format: "%.2f GB", gb)
        }
    }
}

/// Represents cumulative bandwidth consumed over a specific time window.
public struct BandwidthUsage: Sendable, Equatable {
    public let periodType: String   // "month", "day", "session"
    public let periodKey: String    // e.g. "2026-10", "2026-10-25", "session"
    public var bytesIn: UInt64
    public var bytesOut: UInt64
    public var updatedAt: Date

    public init(periodType: String, periodKey: String, bytesIn: UInt64 = 0, bytesOut: UInt64 = 0, updatedAt: Date = Date()) {
        self.periodType = periodType
        self.periodKey = periodKey
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.updatedAt = updatedAt
    }

    public var totalBytes: UInt64 {
        bytesIn + bytesOut
    }

    public var formattedDownload: String {
        NetworkSpeed.formatBytes(bytesIn)
    }

    public var formattedUpload: String {
        NetworkSpeed.formatBytes(bytesOut)
    }

    public var formattedTotal: String {
        NetworkSpeed.formatBytes(totalBytes)
    }

    public var downloadPercentage: Double {
        guard totalBytes > 0 else { return 0.5 }
        return Double(bytesIn) / Double(totalBytes)
    }
}

/// Information about the active primary network interface.
public struct NetworkInterfaceInfo: Sendable, Equatable {
    public let name: String
    public let isConnected: Bool
    public let typeName: String

    public init(name: String = "en0", isConnected: Bool = true, typeName: String = "Wi-Fi") {
        self.name = name
        self.isConnected = isConnected
        self.typeName = typeName
    }

    public var displayName: String {
        if isConnected {
            return "\(typeName) (\(name))"
        } else {
            return "Disconnected"
        }
    }
}
