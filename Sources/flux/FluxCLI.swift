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
            NetCommand.self,
            UpdateCommand.self
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
        On macOS 27 (and 15.8 / 26.7 or later) FluxBar uses the macOS charge limit:
        80-100%, no helper or password needed.
        On older systems a small root helper (com.fluxbar.powerd) enforces any limit from 50%.
        'flux power limit' picks the right one automatically.
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
        let method = ChargeLimitMethod.current
        let installed = PowerHelperManager.isInstalled
        let config = PowerHelperManager.currentConfig()
        let daemon = PowerHelperManager.daemonStatus()
        let nativeLimit = method == .macOS ? NativeChargeLimit.currentLimit() : nil

        if json {
            struct Output: Encodable {
                let battery: BatteryTelemetry
                let method: ChargeLimitMethod
                /// Active limit, 100 when off. Nil if unknown.
                let chargeLimit: Int?
                let limiter: ChargeLimitConfig?
                let helperInstalled: Bool
                let helper: PowerDaemonStatus?
            }
            let active: Int?
            switch method {
            case .macOS: active = nativeLimit
            case .helper: active = installed ? (config.isEnabled ? config.limit : 100) : nil
            case .unavailable: active = nil
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(Output(
                battery: telemetry, method: method, chargeLimit: active,
                limiter: method == .helper ? config : nil,
                helperInstalled: installed, helper: daemon
            ))
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

        switch method {
        case .macOS:
            if let limit = nativeLimit {
                row("Charge limit", limit < 100 ? "\(limit)% · macOS charge limit" : "off (charging to 100%)")
            } else {
                row("Charge limit", "unknown (couldn't read the macOS charge limit)")
            }
            if installed {
                row("Helper", "installed but not needed on this Mac (remove: flux power uninstall)")
            }
        case .helper:
            if installed {
                row("Charge limit", config.isEnabled && config.limit < 100 ? "\(config.limit)% (resumes at \(config.limit - config.hysteresis)%)" : "off")
                if let daemon {
                    row("Helper", "running · \(daemon.reason)")
                } else {
                    row("Helper", "installed, not reporting yet")
                }
            } else {
                row("Charge limit", "helper not installed (run: flux power limit 80)")
            }
        case .unavailable:
            row("Charge limit", "not supported on this Mac")
        }
    }
}

struct PowerLimitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "limit",
        abstract: "Set the charge limit (50-100, or 80-100 on macOS 27), or 'off'"
    )

    @Argument(help: "Percentage, or 'off' to charge normally")
    var value: String

    /// nil = "on" (keep or restore the previous limit), 100 = off.
    private func requested() throws -> Int? {
        switch value.lowercased() {
        case "off", "disable": return 100
        case "on", "enable": return nil
        default:
            guard let pct = Int(value.trimmingCharacters(in: CharacterSet(charactersIn: "% "))), (50...100).contains(pct) else {
                throw ValidationError("Use a number from 50 to 100, or 'off'.")
            }
            return pct
        }
    }

    func run() throws {
        let request = try requested()
        switch ChargeLimitMethod.current {
        case .macOS:
            try Self.applyNative(request)
        case .helper:
            try applyHelper(request)
        case .unavailable:
            throw CLIError("This Mac doesn't support a battery charge limit.")
        }
    }

    static func applyNative(_ request: Int?) throws {
        let current = NativeChargeLimit.currentLimit() ?? 100
        let target = request ?? (current < 100 ? current : 80)
        let applied: Int
        do {
            applied = try NativeChargeLimit.set(target)
        } catch {
            throw CLIError(error.localizedDescription)
        }
        if let request, request < 100, applied != request {
            let options = NativeChargeLimit.availableLimits.map { "\($0)%" }.joined(separator: ", ")
            print("ℹ️  On this Mac the limit is set by macOS, which allows \(options). Using \(applied)%.")
        }
        print(applied < 100
              ? "✅ Charging will hold at \(applied)% (macOS charge limit, also shown in System Settings › Battery)."
              : "✅ Charge limit off. Charging normally to 100%.")
    }

    private func applyHelper(_ request: Int?) throws {
        var config = PowerHelperManager.currentConfig()
        if let request {
            config.limit = ChargeLimitConfig.clampLimit(request)
            config.isEnabled = request < 100
        } else {
            config.isEnabled = true
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
    static let configuration = CommandConfiguration(commandName: "install", abstract: "Install the root helper that enforces the charge limit (older macOS only)")

    @Option(name: .long, help: "Initial charge limit (50-100)")
    var limit: Int?

    func run() throws {
        switch ChargeLimitMethod.current {
        case .macOS:
            print("No helper needed on this Mac: FluxBar uses the macOS charge limit.")
            if let limit {
                try PowerLimitCommand.applyNative(limit)
            } else {
                print("Set it with: flux power limit 80")
            }
        case .helper:
            var config = PowerHelperManager.currentConfig()
            if let limit { config.limit = ChargeLimitConfig.clampLimit(limit); config.isEnabled = config.limit < 100 }
            try Self.runInstaller(config: config)
        case .unavailable:
            throw CLIError("This Mac doesn't support a battery charge limit.")
        }
    }

    static func runInstaller(config: ChargeLimitConfig) throws {
        guard let daemon = PowerHelperManager.bundledDaemonPath() else {
            throw CLIError("com.fluxbar.powerd wasn't found next to flux. Reinstall FluxBar.")
        }
        try sudo([daemon, "install", "--limit", "\(config.limit)", "--enabled", config.isEnabled ? "true" : "false"])
    }
}

struct PowerUninstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "uninstall", abstract: "Remove the root helper and restore normal charging")

    func run() throws {
        let path = FileManager.default.isExecutableFile(atPath: PowerHelperManager.installedBinaryPath)
            ? PowerHelperManager.installedBinaryPath
            : PowerHelperManager.bundledDaemonPath()
        guard let path, PowerHelperManager.isInstalled || FileManager.default.fileExists(atPath: PowerHelperManager.launchDaemonPlistPath) else {
            print("The battery helper isn't installed.")
            if ChargeLimitMethod.current == .macOS {
                print("The macOS charge limit is turned off with: flux power limit off")
            }
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

// =============================================================================
// MARK: - UPDATE (`flux update`)
// =============================================================================

struct UpdateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Update FluxBar to the latest release from GitHub",
        discussion: """
        Checks GitHub for a newer FluxBar, then downloads it, verifies its checksum and code signature,
        and replaces the FluxBar.app that contains this command. A running FluxBar is restarted.
        Your clipboard history and settings are kept.
        """
    )

    @Flag(name: .long, help: "Only check; don't install")
    var check = false

    @Flag(name: [.short, .long], help: "Install without asking")
    var yes = false

    func run() throws {
        let appURL = UpdateEngine.installedAppURL()
        let installed = appURL.flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }
        let current = installed ?? FluxBarInfo.version

        print("Checking for updates…")
        guard let update = try waitFor({ try await UpdateEngine.checkForUpdate(currentVersion: current) }) else {
            print("✅ FluxBar \(current) is the latest version.")
            return
        }
        print("FluxBar \(update.version) is available (you have \(current)).")
        print("Release notes: \(update.release.htmlURL.absoluteString)")
        if check { return }

        guard let appURL else {
            throw CLIError("This flux isn't inside FluxBar.app. Update with the installer instead:\n  curl -fsSL https://raw.githubusercontent.com/\(UpdateEngine.repository)/main/scripts/install.sh | bash")
        }
        if let blocker = UpdateEngine.installBlocker(for: appURL) { throw CLIError(blocker) }

        if !yes {
            guard isatty(STDIN_FILENO) != 0 else { throw CLIError("Run 'flux update --yes' to install without a prompt.") }
            print("Install it now? [Y/n] ", terminator: "")
            let answer = (readLine() ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            guard answer.isEmpty || answer == "y" || answer == "yes" else { print("Cancelled."); return }
        }

        let bundleID = Bundle(url: appURL)?.bundleIdentifier ?? FluxBarInfo.bundleIdentifier
        let interactive = isatty(STDOUT_FILENO) != 0
        let prepared = try waitFor {
            try await UpdateEngine.prepare(update, expectedBundleID: bundleID) { fraction in
                guard interactive else { return }
                let width = 30, filled = Int(fraction * Double(width))
                let bar = String(repeating: "#", count: filled) + String(repeating: "-", count: width - filled)
                FileHandle.standardOutput.write(Data("\rDownloading [\(bar)] \(Int(fraction * 100))%".utf8))
            }
        }
        if interactive { print("") }
        print("Verified FluxBar \(prepared.version).")

        // Ask a running FluxBar from this location to quit; the swap script waits for it.
        let pid = UpdateEngine.runningPIDs(of: appURL).first ?? 0
        if pid != 0 {
            DistributedNotificationCenter.default().postNotificationName(
                UpdateEngine.quitForUpdateNotification, object: nil, userInfo: nil, deliverImmediately: true)
        }
        do {
            try UpdateEngine.launchSwap(prepared, replacing: appURL, waitForPID: pid, relaunch: pid != 0)
        } catch {
            UpdateEngine.discard(prepared)
            throw CLIError(error.localizedDescription)
        }
        print(pid != 0
              ? "✅ Installing FluxBar \(prepared.version). FluxBar will restart in a few seconds."
              : "✅ Installing FluxBar \(prepared.version) into \(appURL.path).")
    }
}

/// Runs async work from a synchronous command and returns its result.
func waitFor<T>(_ work: @escaping @Sendable () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<T, Error>!
    Task.detached {
        do { result = .success(try await work()) } catch { result = .failure(error) }
        semaphore.signal()
    }
    semaphore.wait()
    do {
        return try result.get()
    } catch let error as UpdateError {
        throw CLIError(error.localizedDescription)
    }
}
