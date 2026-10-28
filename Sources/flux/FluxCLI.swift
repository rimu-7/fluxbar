import Foundation
import ArgumentParser
import ClipCore
import PowerCore
import NetCore

@main
struct FluxCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "flux",
        abstract: "FluxBar command line: clipboard history, battery charge limit and network usage.",
        version: FluxBarInfo.version,
        subcommands: [
            ClipCommand.self,
            PowerCommand.self,
            NetCommand.self
        ]
    )
}

// =============================================================================
// MARK: - CLIPBOARD COMMANDS (`flux clip`)
// =============================================================================

struct ClipCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clip",
        abstract: "Manage clipboard history, search clips, and copy/paste",
        subcommands: [
            ClipListCommand.self,
            ClipGetCommand.self,
            ClipCopyCommand.self,
            ClipPasteCommand.self,
            ClipClearCommand.self,
            ClipStatsCommand.self
        ],
        defaultSubcommand: ClipListCommand.self
    )
}

struct ClipListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List recent clips with optional search")

    @Option(name: .shortAndLong, help: "Full-text search query (FTS5)")
    var search: String?

    @Option(name: .shortAndLong, help: "Maximum number of clips to return")
    var limit: Int = 20

    @Flag(name: .shortAndLong, help: "Show only pinned clips")
    var pinned: Bool = false

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() throws {
        let db = DatabaseManager.shared
        let query = search ?? ""
        let clips = try db.queryClips(searchQuery: query, limit: limit, pinnedOnly: pinned)

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(clips)
            if let output = String(data: data, encoding: .utf8) {
                print(output)
            }
            return
        }

        if clips.isEmpty {
            print("No clips found.")
            return
        }

        func pad(_ s: String, _ len: Int) -> String {
            if s.count >= len { return String(s.prefix(len)) }
            return s + String(repeating: " ", count: len - s.count)
        }

        print("\(pad("ID", 6)) \(pad("PIN", 4)) \(pad("COPIES", 7)) \(pad("TIME", 10)) \(pad("SOURCE", 14)) CONTENT PREVIEW")
        print(String(repeating: "-", count: 85))

        for (idx, clip) in clips.enumerated() {
            let pinMark = clip.isPinned ? "📌" : "  "
            let idStr = clip.id != nil ? "#\(clip.id!)" : "#\(idx + 1)"
            let copyStr = "\(clip.copyCount)x"
            let timeStr = clip.relativeTimeText
            let appStr = String((clip.sourceAppName ?? "Unknown").prefix(14))
            let preview = String(clip.previewText.replacingOccurrences(of: "\n", with: " ⏎ ").prefix(40))

            print("\(pad(idStr, 6)) \(pad(pinMark, 4)) \(pad(copyStr, 7)) \(pad(timeStr, 10)) \(pad(appStr, 14)) \(preview)")
        }
    }
}

struct ClipGetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get", abstract: "Display the full content of a specific clip")

    @Argument(help: "Clip numeric ID (e.g. 1)")
    var id: Int64

    @Flag(name: .long, help: "Output as raw JSON")
    var json: Bool = false

    func run() throws {
        let db = DatabaseManager.shared
        guard let clip = try db.fetchClip(id: id) else {
            throw CLIError("Clip #\(id) not found.")
        }

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(clip)
            if let output = String(data: data, encoding: .utf8) {
                print(output)
            }
            return
        }

        print(clip.content)
    }
}

struct ClipCopyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "copy", abstract: "Copy text or a historical clip into the pasteboard")

    @Argument(help: "Text content to copy, or numeric clip ID (e.g. 5)")
    var target: String

    func run() throws {
        let db = DatabaseManager.shared

        if let id = Int64(target.replacingOccurrences(of: "#", with: "")),
           let clip = try db.fetchClip(id: id) {
            MainActor.assumeIsolated {
                PasteboardService.shared.copyToPasteboard(item: clip)
            }
            print("✅ Copied clip #\(id) to pasteboard.")
            return
        }

        let saved = try db.recordClip(content: target, sourceAppName: "Terminal (flux)")
        MainActor.assumeIsolated {
            PasteboardService.shared.copyToPasteboard(item: saved)
        }
        print("✅ Copied to clipboard (\(target.count) characters).")
    }
}

struct ClipPasteCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "paste", abstract: "Print latest or specific clip content to stdout")

    @Argument(help: "Optional numeric clip ID (defaults to most recent)")
    var id: Int64?

    func run() throws {
        let db = DatabaseManager.shared

        if let clipId = id {
            guard let clip = try db.fetchClip(id: clipId) else {
                throw CLIError("Clip #\(clipId) not found.")
            }
            print(clip.content)
        } else {
            // Most recently used, ignoring pin order.
            guard let newest = try db.mostRecentClip() else {
                FileHandle.standardError.write(Data("Clipboard history is empty.\n".utf8))
                throw ExitCode(1)
            }
            print(newest.content)
        }
    }
}

struct ClipClearCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "clear", abstract: "Clear unpinned clipboard history")

    @Flag(name: .shortAndLong, help: "Also delete pinned clips")
    var all: Bool = false

    func run() throws {
        let db = DatabaseManager.shared
        if all {
            try db.deleteAllClips()
            print("✅ Cleared all clipboard history including pinned items.")
        } else {
            try db.clearUnpinned()
            print("✅ Cleared unpinned clipboard history. Pinned items preserved.")
        }
    }
}

struct ClipStatsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "stats", abstract: "Display clipboard database and blob statistics")

    func run() throws {
        let db = DatabaseManager.shared
        let stats = try db.getDatabaseStats()
        let blobSize = ClipBlobManager.shared.totalBlobsSizeBytes
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file

        print("========================================")
        print("  FluxBar Clipboard Storage Stats")
        print("========================================")
        print("Total Clips Saved:      \(stats.totalClips)")
        print("Pinned Clips:           \(stats.pinnedClips)")
        print("SQLite Database Size:   \(stats.formattedFileSize)")
        print("Externalized Blobs:     \(formatter.string(fromByteCount: blobSize))")
        print("Database Path:          \(db.dbPath ?? "In-Memory")")
        print("Blobs Sandbox Path:     \(ClipBlobManager.shared.blobsDirectoryURL.path)")
        print("========================================")
    }
}

// =============================================================================
// MARK: - POWER & BATTERY COMMANDS (`flux power`)
// =============================================================================

struct PowerCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "power",
        abstract: "Battery status and charge limit",
        discussion: """
        The charge limit is enforced by a small root helper (com.fluxbar.powerd).
        Install it once with 'flux power install'; after that 'flux power limit' needs no password.
        """,
        subcommands: [
            PowerStatusCommand.self,
            PowerLimitCommand.self,
            PowerInstallCommand.self,
            PowerUninstallCommand.self
        ],
        defaultSubcommand: PowerStatusCommand.self
    )
}

struct PowerStatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status", abstract: "Show battery, charger and charge limit status")

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() throws {
        let telemetry = BatteryMonitor.fetchTelemetry(deep: true)
        let installed = PowerHelperManager.isInstalled
        let config = PowerHelperManager.currentConfig()
        let daemon = PowerHelperManager.daemonStatus()

        if json {
            struct Output: Encodable {
                let battery: BatteryTelemetry
                let limiter: ChargeLimitConfig
                let helperInstalled: Bool
                let helper: PowerDaemonStatus?
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(Output(battery: telemetry, limiter: config, helperInstalled: installed, helper: daemon))
            print(String(decoding: data, as: UTF8.self))
            return
        }

        func row(_ label: String, _ value: String) {
            print(label.padding(toLength: 18, withPad: " ", startingAt: 0) + value)
        }

        row("Battery", "\(telemetry.percentage)% · \(telemetry.chargingState.statusDescription)")
        row("Power source", telemetry.powerSource)
        row("Health", String(format: "%.1f%% (%@)", telemetry.healthPercentage, telemetry.healthGrade))
        row("Cycles", "\(telemetry.cycleCount)")
        row("Temperature", String(format: "%.1f °C", telemetry.temperature))
        row("Battery power", String(format: "%.1f W", telemetry.wattage))
        if telemetry.isPluggedIn {
            var charger = "\(telemetry.adapterWatts.map { "\($0) W " } ?? "")\(telemetry.adapterName ?? "adapter")"
            if let input = telemetry.inputPowerWatts { charger += String(format: " · drawing %.1f W", input) }
            row("Charger", charger)
        }
        if let minutes = telemetry.timeRemainingMinutes {
            row(telemetry.isCharging ? "Time to full" : "Time left", "\(minutes / 60)h \(minutes % 60)m")
        }
        print("")
        if installed {
            row("Charge limit", config.isEnabled && config.limit < 100 ? "\(config.limit)% (resumes at \(config.limit - config.hysteresis)%)" : "off")
            if let daemon {
                row("Helper", "running · \(daemon.reason)")
                if !daemon.smcWritable { row("", "⚠️  This Mac's charge controller is not supported") }
            } else {
                row("Helper", "installed, not reporting yet")
            }
        } else {
            row("Charge limit", "helper not installed (run: flux power install)")
        }
    }
}

struct PowerLimitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "limit",
        abstract: "Set the charge limit (50-100), or 'off'"
    )

    @Argument(help: "Percentage 50-100, or 'off' to charge normally")
    var value: String

    func run() throws {
        var config = PowerHelperManager.currentConfig()
        switch value.lowercased() {
        case "off", "disable", "100":
            config.isEnabled = false
        case "on", "enable":
            config.isEnabled = true
        default:
            guard let pct = Int(value.trimmingCharacters(in: CharacterSet(charactersIn: "% "))), (50...100).contains(pct) else {
                throw ValidationError("Use a number from 50 to 100, or 'off'.")
            }
            config.limit = pct
            config.isEnabled = pct < 100
        }

        guard PowerHelperManager.isInstalled else {
            print("The battery helper isn't installed yet. Installing (needs your password once)…")
            try PowerInstallCommand.runInstaller(config: config)
            return
        }
        do {
            try PowerHelperManager.save(config)
        } catch {
            throw CLIError("Couldn't save the limit (\(error.localizedDescription)). Only admin users can change it.")
        }
        print(config.isEnabled ? "✅ Charging will hold at \(config.limit)%." : "✅ Limiter off. Charging normally to 100%.")
    }
}

struct PowerInstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "install", abstract: "Install the root helper that enforces the charge limit")

    @Option(name: .long, help: "Initial charge limit (50-100)")
    var limit: Int?

    func run() throws {
        var config = PowerHelperManager.currentConfig()
        if let limit { config.limit = ChargeLimitConfig.clampLimit(limit); config.isEnabled = config.limit < 100 }
        try Self.runInstaller(config: config)
    }

    static func runInstaller(config: ChargeLimitConfig) throws {
        guard let daemon = PowerHelperManager.bundledDaemonPath() else {
            throw CLIError("com.fluxbar.powerd wasn't found next to flux. Reinstall FluxBar.")
        }
        try sudo([daemon, "install", "--limit", "\(config.limit)", "--enabled", config.isEnabled ? "true" : "false"])
    }
}

struct PowerUninstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "uninstall", abstract: "Remove the helper and restore normal charging")

    func run() throws {
        let path = FileManager.default.isExecutableFile(atPath: PowerHelperManager.installedBinaryPath)
            ? PowerHelperManager.installedBinaryPath
            : PowerHelperManager.bundledDaemonPath()
        guard let path else {
            print("The battery helper isn't installed.")
            return
        }
        try sudo([path, "uninstall"])
    }
}

/// A runtime failure: printed as "Error: …" without the usage text, exit code 1.
struct CLIError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

/// Runs a command as root, prompting for the password in the terminal when needed.
func sudo(_ command: [String]) throws {
    let process = Process()
    if geteuid() == 0 {
        process.executableURL = URL(fileURLWithPath: command[0])
        process.arguments = Array(command.dropFirst())
    } else {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = command
    }
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        throw ExitCode(process.terminationStatus)
    }
}

// =============================================================================
// MARK: - NETWORK SPEED & BANDWIDTH COMMANDS (`flux net`)
// =============================================================================

struct NetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "net",
        abstract: "Kernel-level network throughput monitoring and bandwidth accounting",
        subcommands: [
            NetStatsCommand.self,
            NetLiveCommand.self
        ],
        defaultSubcommand: NetStatsCommand.self
    )
}

struct NetStatsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "stats", abstract: "Display current network speeds and bandwidth consumption")

    @Flag(name: .long, help: "Output as raw JSON")
    var json: Bool = false

    func run() throws {
        // Measure for one second instead of starting the app's monitor.
        let sampler = NetworkByteSampler()
        let before = sampler.queryBytes(forInterface: nil)
        Thread.sleep(forTimeInterval: 1.0)
        let after = sampler.queryBytes(forInterface: nil)
        let speed = NetworkSpeed(
            bytesInPerSec: NetworkByteSampler.computeDelta(current: after.bytesIn, previous: before.bytesIn),
            bytesOutPerSec: NetworkByteSampler.computeDelta(current: after.bytesOut, previous: before.bytesOut)
        )
        let store = BandwidthStore.shared
        let todayUsage = store.getTodayUsage()
        let monthUsage = store.getCurrentMonthUsage()

        if json {
            let dict: [String: Any] = [
                "uploadBytesPerSec": speed.bytesOutPerSec,
                "downloadBytesPerSec": speed.bytesInPerSec,
                "uploadFormatted": speed.formattedUpload,
                "downloadFormatted": speed.formattedDownload,
                "todayUsageBytes": todayUsage.totalBytes,
                "monthlyUsageBytes": monthUsage.totalBytes
            ]
            let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("Upload       \(speed.formattedUpload)")
        print("Download     \(speed.formattedDownload)")
        print("Today        \(todayUsage.formattedTotal)")
        print("This month   \(monthUsage.formattedTotal)")
    }
}

struct NetLiveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "live", abstract: "Continuously stream live upload and download rates")

    func run() throws {
        let sampler = NetworkByteSampler()
        print("📶 Streaming live network throughput (Press Ctrl+C to exit)...")
        print(String(repeating: "-", count: 50))
        var prev = sampler.queryBytes(forInterface: nil)

        while true {
            Thread.sleep(forTimeInterval: 1.0)
            let curr = sampler.queryBytes(forInterface: nil)
            let downBytes = NetworkByteSampler.computeDelta(current: curr.bytesIn, previous: prev.bytesIn)
            let upBytes = NetworkByteSampler.computeDelta(current: curr.bytesOut, previous: prev.bytesOut)
            prev = curr

            let upFormatted = NetworkSpeed.formatRate(upBytes)
            let downFormatted = NetworkSpeed.formatRate(downBytes)
            print("↑ \(upFormatted.padding(toLength: 12, withPad: " ", startingAt: 0))  ↓ \(downFormatted)")
            fflush(stdout)
        }
    }
}
