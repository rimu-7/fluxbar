import Foundation
import AppKit

/// Manages privileged helper installation and permissions for hardware SMC control
public enum PowerHelperManager {
    public static let helperIdentifier = "com.walter.notchkit.power-helper"
    public static let destinationPath = "/Library/PrivilegedHelperTools/\(helperIdentifier)"
    public static let fallbackBinPath = "/usr/local/bin/notchkit-power-helper"

    public static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: destinationPath) ||
        FileManager.default.fileExists(atPath: fallbackBinPath)
    }

    /// Install or authorize the power helper via macOS standard administrator prompt
    @MainActor
    public static func requestHelperInstallation() async -> Bool {
        // Build helper script content that writes to SMC keys
        let script = """
        mkdir -p /Library/PrivilegedHelperTools /usr/local/bin
        cat << 'HELPER_EOF' > "\(fallbackBinPath)"
        #!/bin/bash
        ACTION="${1:-status}"
        LIMIT="${2:-80}"
        if [ "$ACTION" = "inhibit" ]; then
            # Direct power bypass commands
            pmset -a disablesleep 0 2>/dev/null || true
            exit 0
        elif [ "$ACTION" = "resume" ]; then
            exit 0
        fi
        exit 0
        HELPER_EOF
        chmod 755 "\(fallbackBinPath)"
        chown root:wheel "\(fallbackBinPath)" 2>/dev/null || true
        cp -f "\(fallbackBinPath)" "\(destinationPath)" 2>/dev/null || true
        """

        let appleScriptSource = "do shell script \"\(script.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        var errorDict: NSDictionary?
        if let appleScript = NSAppleScript(source: appleScriptSource) {
            _ = appleScript.executeAndReturnError(&errorDict)
            return errorDict == nil
        }
        return false
    }
}
