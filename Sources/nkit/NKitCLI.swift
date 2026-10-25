import Foundation
import ArgumentParser
import ClipCore
import PowerCore
import NetCore

@main
struct NKitCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "nkit",
        abstract: "NotchKit Unified macOS Menu Bar & Hardware Power, Network, and Clipboard CLI",
        version: "1.1.0",
        subcommands: [
            ClipCommand.self,
            PowerCommand.self,
            NetCommand.self
        ],
        defaultSubcommand: PowerCommand.self
    )
}

// =============================================================================
// MARK: - CLIPBOARD COMMANDS (`nkit clip`)
// =============================================================================

struct ClipCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clip",
        abstract: "Manage clipboard history, search clips, and copy/paste",
        subcommands: [
            ClipListCommand.self,
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

struct ClipCopyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "copy", abstract: "Copy text or a historical clip into the pasteboard")

    @Argument(help: "Text content to copy, or numeric clip ID (e.g. 5)")
    var target: String

    func run() throws {
        let db = DatabaseManager.shared
        let clips = try db.queryClips(searchQuery: "", limit: 1000)

        if let id = Int64(target.replacingOccurrences(of: "#", with: "")),
           let clip = clips.first(where: { $0.id == id }) {
            MainActor.assumeIsolated {
                PasteboardService.shared.copyToPasteboard(item: clip)
            }
            print("✅ Copied clip #\(id) to pasteboard.")
            return
        }

        let saved = try db.recordClip(content: target, sourceAppName: "Terminal (nkit)")
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
        let clips = try db.queryClips(searchQuery: "", limit: 100)

        if let clipId = id {
            guard let clip = clips.first(where: { $0.id == clipId }) else {
                print("Error: Clip #\(clipId) not found.")
                return
            }
            print(clip.content)
        } else {
            guard let latest = clips.first else {
                print("Clipboard history is empty.")
                return
            }
            print(latest.content)
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
        print("  NotchKit Clipboard Storage Stats")
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
// MARK: - POWER & BATTERY COMMANDS (`nkit power`)
// =============================================================================

struct PowerCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "power",
        abstract: "Apple Silicon & Intel hardware battery limiter, SMC bypass, and live power analytics",
        subcommands: [
            PowerStatusCommand.self,
            PowerLimitCommand.self,
            PowerBypassCommand.self,
            PowerMagSafeCommand.self
        ],
        defaultSubcommand: PowerStatusCommand.self
    )
}

struct PowerStatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status", abstract: "Show comprehensive battery, charger, and peripheral telemetry")

    @Flag(name: .long, help: "Output as raw JSON")
    var json: Bool = false

    func run() throws {
        let monitor = BatteryMonitor.shared
        let telemetry = monitor.currentTelemetry
        let limiter = ChargeLimiter.shared

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(telemetry)
            if let output = String(data: data, encoding: .utf8) {
                print(output)
            }
            return
        }

        print("====================================================================")
        print("  ⚡️ NotchKit Power & Battery Hardware Telemetry")
        print("====================================================================")
        print("Battery Level:          \(telemetry.percentage)% (\(telemetry.chargingState.statusDescription))")
        print("Power Source:           \(telemetry.powerSource)")
        print("Health Status:          \(String(format: "%.1f%%", telemetry.healthPercentage)) (\(telemetry.healthGrade))")
        print("Cycle Count:            \(telemetry.cycleCount) / \(telemetry.ratedCycles) rated cycles")
        print("Cell Temperature:       \(String(format: "%.1f°C", telemetry.temperature)) (\(telemetry.thermalStateDescription))")
        print("Voltage Rail:           \(String(format: "%.2f V", Double(telemetry.voltage) / 1000.0)) (\(telemetry.voltage) mV)")
        print("Amperage Flow:          \(telemetry.amperage) mA")
        print("Battery Wattage:        \(String(format: "%.1f W", telemetry.wattage))")

        print("--------------------------------------------------------------------")
        print("  🔌 Charger Hardware & Live Power Input")
        print("--------------------------------------------------------------------")
        if telemetry.isPluggedIn {
            let watts = telemetry.adapterWatts ?? 0
            let name = telemetry.adapterName ?? "PD Charger"
            print("Adapter Status:         Connected (\(watts)W \(name))")
            if let port = telemetry.chargerPortIndex {
                print("Connection Port:        Thunderbolt / USB-C Port \(port)")
            }
            if let liveWatts = telemetry.inputPowerWatts {
                print("Live Negotiated Input:  \(String(format: "%.1f W", liveWatts)) (\(String(format: "%.0f%%", (liveWatts / max(1.0, Double(watts))) * 100)) of capacity)")
            }
            if let inVolt = telemetry.inputVoltage ?? telemetry.adapterVoltage {
                print("Input Voltage Rail:     \(String(format: "%.1f V", inVolt)) DC")
            }
            if let inAmp = telemetry.inputCurrentAmps ?? telemetry.adapterAmperage {
                print("Input Current Draw:     \(String(format: "%.2f A", inAmp)) (Max \(String(format: "%.2f A", telemetry.adapterAmperage ?? 5.0)))")
            }
            if !telemetry.adapterProfiles.isEmpty {
                print("Supported PD Profiles:  \(telemetry.adapterProfiles.joined(separator: " • "))")
            }
        } else {
            print("Adapter Status:         Unplugged (Running on internal battery)")
            if let lastWatts = telemetry.adapterWatts {
                print("Last Connected:         \(lastWatts)W \(telemetry.adapterName ?? "PD Charger")")
            }
        }

        print("--------------------------------------------------------------------")
        print("  📱 Reverse Charging (Peripheral Power Delivery)")
        print("--------------------------------------------------------------------")
        if !telemetry.connectedAccessories.isEmpty {
            for acc in telemetry.connectedAccessories {
                let battStr = acc.batteryLevel != nil ? " [Battery: \(acc.batteryLevel!)%]" : ""
                print("• \(acc.deviceName) on \(acc.portName): Sourcing ~\(String(format: "%.1f W", acc.estimatedOutputWatts))\(battStr)")
            }
        } else {
            print("Connected Devices:      0 (Ports ready for reverse PD up to 15W per port)")
        }

        print("--------------------------------------------------------------------")
        print("  🛡️ Hardware SMC Charge Limiter & AC Bypass")
        print("--------------------------------------------------------------------")
        print("Charge Limiter:         \(limiter.isLimiterEnabled ? "Enabled (Target: \(limiter.chargeLimit)%)" : "Disabled (100% full charge)")")
        print("Hardware AC Bypass:     \(limiter.isAdapterBypassActive ? "ACTIVE (Running 100% from wall adapter)" : "Inactive")")
        print("SMC Generation:         \(SMCService.shared.detectedHardwareGeneration.rawValue)")
        print("Helper Tool Status:     \(SMCService.shared.isHelperInstalled ? "Installed & Authorized" : "Not Authorized (Run 'nkit power authorize')")")
        print("====================================================================")
    }
}

struct PowerLimitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "limit", abstract: "Set hardware battery charge limit percentage")

    @Argument(help: "Target percentage limit: 50, 60, 70, 80, 85, 90, 95, or 100")
    var percentage: Int

    func run() throws {
        let clamped = max(50, min(100, percentage))
        let limiter = ChargeLimiter.shared

        if clamped == 100 {
            limiter.setEnabled(false)
            SMCService.shared.setChargingInhibited(false, limitPercentage: 100)
            print("✅ Hardware charge limiter disabled. MacBook will charge up to 100%.")
        } else {
            limiter.configure(isEnabled: true, limit: clamped, hysteresis: 3)
            let success = SMCService.shared.setChargingInhibited(true, limitPercentage: clamped)
            if success {
                print("✅ Charge limit set to \(clamped)%. Hardware AC bypass will engage at \(clamped)%.")
            } else {
                print("⚠️ Charge limit updated in software to \(clamped)%. SMC hardware write requires privilege authorization.")
                print("   Run: sudo nkit power limit \(clamped)")
            }
        }
    }
}

struct PowerBypassCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "bypass", abstract: "Manually toggle AC adapter direct bypass")

    @Argument(help: "State: on or off")
    var state: String

    func run() throws {
        let enable = (state.lowercased() == "on" || state.lowercased() == "1" || state.lowercased() == "true")
        let success = SMCService.shared.setChargingInhibited(enable, limitPercentage: 80)
        if success {
            print("✅ Direct AC adapter bypass set to: \(enable ? "ON (Charging Inactive)" : "OFF (Normal Charging)")")
        } else {
            print("⚠️ Could not toggle bypass directly. Elevated privileges required.")
            print("   Run: sudo nkit power bypass \(state)")
        }
    }
}

struct PowerMagSafeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "magsafe", abstract: "Set MagSafe 3 LED indicator color")

    @Argument(help: "Color: green or auto")
    var color: String

    func run() throws {
        let isGreen = (color.lowercased() == "green" || color.lowercased() == "on")
        let success = SMCService.shared.setMagSafeLED(green: isGreen)
        if success {
            print("✅ MagSafe 3 LED set to: \(isGreen ? "Green (Bypass / Full)" : "Auto (Apple Default)")")
        } else {
            print("⚠️ Could not adjust MagSafe LED directly. Elevated privileges required.")
        }
    }
}

// =============================================================================
// MARK: - NETWORK SPEED & BANDWIDTH COMMANDS (`nkit net`)
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
        let monitor = NetworkSpeedMonitor.shared
        let speed = monitor.currentSpeed
        let todayUsage = monitor.todayUsage
        let monthUsage = monitor.monthUsage
        let ifInfo = monitor.interfaceInfo

        if json {
            let dict: [String: Any] = [
                "uploadBytesPerSec": speed.bytesOutPerSec,
                "downloadBytesPerSec": speed.bytesInPerSec,
                "uploadFormatted": speed.formattedUpload,
                "downloadFormatted": speed.formattedDownload,
                "interface": ifInfo.name,
                "interfaceType": ifInfo.typeName,
                "todayUsageBytes": todayUsage.totalBytes,
                "monthlyUsageBytes": monthUsage.totalBytes
            ]
            let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
            if let output = String(data: data, encoding: .utf8) {
                print(output)
            }
            return
        }

        print("====================================================================")
        print("  📶 NotchKit Real-Time Network & Bandwidth Stats")
        print("====================================================================")
        print("Upload Rate (↑):        \(speed.formattedUpload)")
        print("Download Rate (↓):      \(speed.formattedDownload)")
        print("Primary Interface:      \(ifInfo.displayName)")
        print("Today's Data Usage:     \(todayUsage.formattedTotal)")
        print("Monthly Data Usage:     \(monthUsage.formattedTotal)")
        print("Sampling Architecture:  Direct BSD Kernel sysctl (NET_RT_IFLIST2)")
        print("====================================================================")
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
