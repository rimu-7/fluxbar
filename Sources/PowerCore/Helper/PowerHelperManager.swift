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
        return fm.fileExists(atPath: installedBinaryPath)
            && fm.fileExists(atPath: launchDaemonPlistPath)
            && fm.fileExists(atPath: ChargeLimitConfig.directoryURL.path)
    }

    /// True when the current user may change the limit without a password (admin group, helper installed).
    public static var canWriteConfig: Bool {
        FileManager.default.isWritableFile(atPath: ChargeLimitConfig.directoryURL.path)
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
        let args = "install --limit \(config.limit) --enabled \(config.isEnabled ? "true" : "false")"
        try await runWithAdminPrompt(executable: daemon, arguments: args)
    }

    public static func uninstallWithAdminPrompt() async throws {
        let daemon = FileManager.default.isExecutableFile(atPath: installedBinaryPath) ? installedBinaryPath : bundledDaemonPath()
        guard let daemon else { throw HelperError.daemonBinaryMissing }
        try await runWithAdminPrompt(executable: daemon, arguments: "uninstall")
    }

    private static func runWithAdminPrompt(executable: String, arguments: String) async throws {
        let escaped = executable
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script (quoted form of \"\(escaped)\") & \" \(arguments)\" with prompt \"FluxBar needs permission to manage battery charging.\" with administrator privileges"

        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        guard status == 0 else { throw HelperError.cancelledOrFailed }
    }

    public enum HelperError: LocalizedError {
        case notInstalled
        case daemonBinaryMissing
        case cancelledOrFailed

        public var errorDescription: String? {
            switch self {
            case .notInstalled:
                return "The battery helper is not installed. Run 'flux power install' or use Install in the app."
            case .daemonBinaryMissing:
                return "Could not find com.fluxbar.powerd next to this app. Reinstall FluxBar."
            case .cancelledOrFailed:
                return "Authorization was cancelled or the install failed."
            }
        }
    }
}
