import Foundation

/// Charge limit settings shared between the app, the `flux` CLI and the root `com.fluxbar.powerd` daemon.
///
/// The daemon is the only process that writes to the SMC. The app and CLI just save this file;
/// the daemon watches the folder and applies the change within a second.
public struct ChargeLimitConfig: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    public var limit: Int
    /// Charging resumes once the battery falls to `limit - hysteresis`.
    public var hysteresis: Int

    public init(isEnabled: Bool = true, limit: Int = 80, hysteresis: Int = 3) {
        self.isEnabled = isEnabled
        self.limit = Self.clampLimit(limit)
        self.hysteresis = max(1, min(10, hysteresis))
    }

    public static let `default` = ChargeLimitConfig()

    public static func clampLimit(_ value: Int) -> Int { max(50, min(100, value)) }

    // MARK: - Locations

    /// Root-owned folder, group `admin`, mode 0775: admin users may update the settings, nobody else.
    public static let directoryURL = URL(fileURLWithPath: "/Library/Application Support/FluxBar", isDirectory: true)
    public static let fileURL = directoryURL.appendingPathComponent("charge-limit.json")
    public static let statusFileURL = directoryURL.appendingPathComponent("powerd-status.json")

    // MARK: - Read / Write

    public static func load(from url: URL = fileURL) -> ChargeLimitConfig? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let decoded = try? JSONDecoder().decode(ChargeLimitConfig.self, from: data) else { return nil }
        // Re-run init so out-of-range values written by hand are clamped.
        return ChargeLimitConfig(isEnabled: decoded.isEnabled, limit: decoded.limit, hysteresis: decoded.hysteresis)
    }

    /// Atomically saves the settings. Throws when the helper is not installed (folder missing or not writable).
    public func save(to url: URL = fileURL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}

/// What the daemon last did. Written by the daemon, read by the app and CLI.
public struct PowerDaemonStatus: Codable, Sendable, Equatable {
    public var isChargingInhibited: Bool
    public var reason: String
    public var hardware: String
    public var smcWritable: Bool
    public var updatedAt: Date

    public init(isChargingInhibited: Bool, reason: String, hardware: String, smcWritable: Bool, updatedAt: Date = Date()) {
        self.isChargingInhibited = isChargingInhibited
        self.reason = reason
        self.hardware = hardware
        self.smcWritable = smcWritable
        self.updatedAt = updatedAt
    }

    public static func load(from url: URL = ChargeLimitConfig.statusFileURL) -> PowerDaemonStatus? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(PowerDaemonStatus.self, from: data)
    }

    public func save(to url: URL = ChargeLimitConfig.statusFileURL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: url, options: .atomic)
        // World-readable so the app and CLI can show it.
        chmod(url.path, 0o644)
    }
}
