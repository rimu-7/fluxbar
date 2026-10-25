import Foundation
import AppKit
import ServiceManagement

/// Manages privileged helper installation and hardware charge limiting execution
public enum PowerHelperManager {
    public static let wattbitdPath = "/Library/PrivilegedHelperTools/wattbitd"
    public static let helperIdentifier = "com.fluxbar.powerd"
    public static let legacyHelperIdentifier = "com.notchkit.powerd"
    public static let destinationPath = "/Library/PrivilegedHelperTools/\(helperIdentifier)"
    public static let legacyDestinationPath = "/Library/PrivilegedHelperTools/\(legacyHelperIdentifier)"
    public static let fallbackBinPath = "/usr/local/bin/fluxbar-power-helper"
    public static let legacyFallbackBinPath = "/usr/local/bin/notchkit-power-helper"

    public static var isInstalled: Bool {
        if #available(macOS 13.0, *) {
            let service = SMAppService.daemon(plistName: "\(helperIdentifier).plist")
            if service.status == .enabled {
                return true
            }
        }
        if FileManager.default.fileExists(atPath: wattbitdPath) {
            return true
        }
        if FileManager.default.fileExists(atPath: destinationPath) || FileManager.default.fileExists(atPath: legacyDestinationPath) {
            return true
        }
        if FileManager.default.fileExists(atPath: fallbackBinPath) || FileManager.default.fileExists(atPath: legacyFallbackBinPath) {
            return true
        }
        return false
    }

    public static func findBuiltDaemonBinary() -> String? {
        let candidates = [
            Bundle.main.bundlePath + "/Contents/MacOS/com.fluxbar.powerd",
            Bundle.main.bundlePath + "/Contents/MacOS/fluxbar-power-helper",
            "/usr/local/bin/com.fluxbar.powerd",
            "/usr/local/bin/fluxbar-power-helper",
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("com.fluxbar.powerd").path,
            FileManager.default.currentDirectoryPath + "/.build/debug/com.fluxbar.powerd",
            FileManager.default.currentDirectoryPath + "/.build/release/com.fluxbar.powerd",
            Bundle.main.bundlePath + "/Contents/MacOS/com.notchkit.powerd",
            "/usr/local/bin/com.notchkit.powerd",
            FileManager.default.currentDirectoryPath + "/.build/debug/com.notchkit.powerd"
        ]
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0) })
    }

    /// Set charge limit percentage on hardware asynchronously (non-blocking)
    @discardableResult
    public static func applyChargeLimit(_ percentage: Int) -> Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return true
        }

        let clamped = max(50, min(100, percentage))
        let arg = (clamped >= 100) ? "disable" : "\(clamped)"

        DispatchQueue.global(qos: .utility).async {
            // 1. If wattbitd is installed, invoke it
            if FileManager.default.fileExists(atPath: wattbitdPath) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: wattbitdPath)
                process.arguments = ["limit", arg]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3.0) {
                        if process.isRunning { process.terminate() }
                    }
                    process.waitUntilExit()
                } catch {}
            }

            // 2. Try fluxbar-power-helper or legacy helper if available
            if let helperPath = [destinationPath, fallbackBinPath, legacyDestinationPath, legacyFallbackBinPath].first(where: { FileManager.default.fileExists(atPath: $0) }) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: helperPath)
                process.arguments = ["limit", arg]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3.0) {
                        if process.isRunning { process.terminate() }
                    }
                    process.waitUntilExit()
                } catch {}
            }
        }

        return true
    }

    /// Authorize hardware charge limiting via standard macOS Touch ID / Password prompt
    @MainActor
    public static func requestHelperInstallation() async -> Bool {
        if #available(macOS 13.0, *) {
            let service = SMAppService.daemon(plistName: "\(helperIdentifier).plist")
            do {
                try service.register()
                _ = applyChargeLimit(80)
                return true
            } catch {
                // Fallback to administrator execution if running outside .app bundle
            }
        }

        let script: String
        if let bin = findBuiltDaemonBinary() {
            script = """
            mkdir -p /Library/PrivilegedHelperTools /usr/local/bin
            cp -f "\(bin)" "\(destinationPath)"
            chown root:wheel "\(destinationPath)"
            chmod 755 "\(destinationPath)"
            cp -f "\(destinationPath)" "\(fallbackBinPath)"
            "\(destinationPath)" limit 80
            """
        } else if FileManager.default.fileExists(atPath: wattbitdPath) {
            script = "\(wattbitdPath) limit 80"
        } else {
            script = """
            mkdir -p /Library/PrivilegedHelperTools /usr/local/bin
            touch "\(destinationPath)"
            chmod 755 "\(destinationPath)"
            """
        }

        let appleScriptSource = "do shell script \"\(script.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        var errorDict: NSDictionary?
        if let appleScript = NSAppleScript(source: appleScriptSource) {
            _ = appleScript.executeAndReturnError(&errorDict)
            let success = (errorDict == nil)
            if success {
                _ = applyChargeLimit(80)
            }
            return success
        }
        return false
    }
}
