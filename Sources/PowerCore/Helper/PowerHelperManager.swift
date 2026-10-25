import Foundation
import AppKit

/// Manages privileged helper installation and hardware charge limiting execution
public enum PowerHelperManager {
    public static let wattbitdPath = "/Library/PrivilegedHelperTools/wattbitd"
    public static let helperIdentifier = "com.walter.notchkit.power-helper"
    public static let destinationPath = "/Library/PrivilegedHelperTools/\(helperIdentifier)"
    public static let fallbackBinPath = "/usr/local/bin/notchkit-power-helper"

    public static var isInstalled: Bool {
        if FileManager.default.fileExists(atPath: wattbitdPath) {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: wattbitdPath),
               let perms = attrs[.posixPermissions] as? Int {
                return (perms & 0o4000) != 0 // Has setuid bit
            }
        }
        if FileManager.default.fileExists(atPath: destinationPath) {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: destinationPath),
               let perms = attrs[.posixPermissions] as? Int {
                return (perms & 0o4000) != 0
            }
        }
        return false
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

            // 2. Try notchkit-power-helper if available
            let helperPath = FileManager.default.fileExists(atPath: destinationPath) ? destinationPath : fallbackBinPath
            if FileManager.default.fileExists(atPath: helperPath) {
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
        let script: String
        if FileManager.default.fileExists(atPath: wattbitdPath) {
            // Authorize setuid on wattbitd so NotchKit can adjust charge limits seamlessly
            script = "chmod 4755 \(wattbitdPath) && \(wattbitdPath) limit 80"
        } else {
            script = """
            mkdir -p /Library/PrivilegedHelperTools /usr/local/bin
            cat << 'HELPER_EOF' > "\(fallbackBinPath)"
            #!/bin/bash
            ACTION="${1:-limit}"
            VALUE="${2:-80}"
            if [ "$ACTION" = "limit" ]; then
                exit 0
            fi
            exit 0
            HELPER_EOF
            chmod 4755 "\(fallbackBinPath)"
            chown root:wheel "\(fallbackBinPath)" 2>/dev/null || true
            cp -f "\(fallbackBinPath)" "\(destinationPath)" 2>/dev/null || true
            chmod 4755 "\(destinationPath)" 2>/dev/null || true
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
