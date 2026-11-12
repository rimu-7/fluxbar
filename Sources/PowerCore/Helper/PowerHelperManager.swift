import Foundation

/// Installs, removes and talks to the root charge-limit daemon (`com.fluxbar.powerd`).
///
/// Design: the daemon runs as a LaunchDaemon and is the only thing that writes the SMC.
/// Everyone else just saves `ChargeLimitConfig`, which the daemon watches.
/// This needs no code signing team, no XPC, and keeps working when the app is quit.
public enum PowerHelperManager {
    public static let label = "com.fluxbar.powerd"
    public static let installedBinaryPath = "/Library/PrivilegedHelperTools/com.fluxbar.powerd"
    public static let launchDaemonPlistPath = "/Library/LaunchDaemons/com.fluxbar.powerd.plist"

    /// Files left behind by older builds. Removed on install/uninstall.
    public static let legacyPaths = [
        "/usr/local/bin/fluxbar-power-helper",
        "/usr/local/bin/notchkit-power-helper",
        "/usr/local/bin/com.fluxbar.powerd",
        "/Library/PrivilegedHelperTools/com.notchkit.powerd"
    ]

    public static var isInstalled: Bool {
        let fm = FileManager.default
        return fm.isExecutableFile(atPath: installedBinaryPath)
            && fm.fileExists(atPath: launchDaemonPlistPath)
            && fm.fileExists(atPath: ChargeLimitConfig.fileURL.path)
    }

    /// True when the current user may change the limit without a password (admin group, helper installed).
    public static var canWriteConfig: Bool {
        FileManager.default.isWritableFile(atPath: ChargeLimitConfig.directoryURL.path)
    }

    /// A DMG replacement updates the app but leaves an older root helper in place.
    public static var needsUpdate: Bool {
        guard isInstalled, let bundled = bundledDaemonPath() else { return false }
        return !FileManager.default.contentsEqual(atPath: bundled, andPath: installedBinaryPath)
    }

    // MARK: - Settings

    public static func currentConfig() -> ChargeLimitConfig {
        ChargeLimitConfig.load() ?? .default
    }

    public static func daemonStatus() -> PowerDaemonStatus? {
        PowerDaemonStatus.load()
    }

    /// Saves new settings for the daemon. Throws if the helper is not installed.
    public static func save(_ config: ChargeLimitConfig) throws {
        guard isInstalled else { throw HelperError.notInstalled }
        try config.save()
    }

    // MARK: - Locating the daemon binary

    /// Finds the daemon binary shipped next to the running app or CLI.
    public static func bundledDaemonPath() -> String? {
        let fm = FileManager.default
        var candidates: [String] = []

        // Inside FluxBar.app/Contents/MacOS (app, or CLI symlinked into PATH)
        let exec = (Bundle.main.executablePath ?? CommandLine.arguments[0])
        let resolved = URL(fileURLWithPath: exec).resolvingSymlinksInPath()
        candidates.append(resolved.deletingLastPathComponent().appendingPathComponent(label).path)
        candidates.append(Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/\(label)").path)

        // Development builds
        let cwd = fm.currentDirectoryPath
        candidates.append("\(cwd)/.build/release/\(label)")
        candidates.append("\(cwd)/.build/debug/\(label)")

        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }

    // MARK: - Install / Uninstall (GUI: one password / Touch ID prompt)

    /// Installs the daemon through the standard macOS administrator prompt.
    /// Runs `osascript` in a child process so the UI never blocks.
    public static func installWithAdminPrompt(config: ChargeLimitConfig) async throws {
        guard let daemon = bundledDaemonPath() else { throw HelperError.daemonBinaryMissing }
        let args = ["install", "--limit", String(config.limit), "--enabled", config.isEnabled ? "true" : "false"]
        try await runWithAdminPrompt(executable: daemon, arguments: args)
        guard isInstalled else { throw HelperError.notInstalled }
    }

    public static func uninstallWithAdminPrompt() async throws {
        let daemon = FileManager.default.isExecutableFile(atPath: installedBinaryPath) ? installedBinaryPath : bundledDaemonPath()
        guard let daemon else { throw HelperError.daemonBinaryMissing }
        try await runWithAdminPrompt(executable: daemon, arguments: ["uninstall"])
    }

    /// Quote the complete command before embedding it in AppleScript. App folders may contain
    /// spaces, apostrophes, quotes or shell metacharacters.
    static func authorizationScript(executable: String, arguments: [String]) -> String {
        let command = shellCommand(executable: executable, arguments: arguments)
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "do shell script \"\(escaped)\" with prompt \"FluxBar needs permission to manage battery charging.\" with administrator privileges"
    }

    static func shellCommand(executable: String, arguments: [String]) -> String {
        ([executable] + arguments).map {
            "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }.joined(separator: " ")
    }

    private static func runWithAdminPrompt(executable: String, arguments: [String]) async throws {
        let script = authorizationScript(executable: executable, arguments: arguments)
        // A file avoids a full stderr pipe blocking osascript before it exits.
        let errorURL = FileManager.default.temporaryDirectory.appendingPathComponent("fluxbar-authorization-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: errorURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let errorFile = try FileHandle(forWritingTo: errorURL)
        defer {
            try? errorFile.close()
            try? FileManager.default.removeItem(at: errorURL)
        }

        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = errorFile
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        guard status == 0 else {
            let details = (try? String(contentsOf: errorURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if details.contains("(-128)") { throw HelperError.cancelledOrFailed }
            throw HelperError.authorizationFailed(details.isEmpty ? "Please try again from Battery settings." : details)
        }
    }

    public enum HelperError: LocalizedError {
        case notInstalled
        case daemonBinaryMissing
        case cancelledOrFailed
        case authorizationFailed(String)

        public var errorDescription: String? {
            switch self {
            case .notInstalled:
                return "Battery controls need setup. Open the Battery tab and choose Enable."
            case .daemonBinaryMissing:
                return "Could not find com.fluxbar.powerd next to this app. Reinstall FluxBar."
            case .cancelledOrFailed:
                return "Authorization was cancelled. No new battery limit was applied. Choose Enable to try again."
            case .authorizationFailed(let details):
                return "Battery setup failed: \(details)"
            }
        }
    }
}
