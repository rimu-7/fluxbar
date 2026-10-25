import Foundation
import ServiceManagement

/// Helper for toggling and querying macOS Start at Login status.
/// Supports both native macOS 13+ SMAppService and LaunchAgent plist fallback.
public enum LaunchAtLoginHelper {
    private static let launchAgentLabel = "com.fluxbar.FluxBar"

    private static var launchAgentPlistURL: URL {
        let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        return launchAgentsDir.appendingPathComponent("\(launchAgentLabel).plist")
    }

    private static var legacyLaunchAgentPlistURLs: [URL] {
        let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        return [
            launchAgentsDir.appendingPathComponent("com.notchkit.NotchKit.plist"),
            launchAgentsDir.appendingPathComponent("com.clipsuite.ClipBar.plist")
        ]
    }

    public static var isEnabled: Bool {
        // 1. Check macOS 13+ SMAppService if running inside a bundle
        if Bundle.main.bundleIdentifier != nil {
            let status = SMAppService.mainApp.status
            if status == .enabled {
                return true
            }
        }

        // 2. Check LaunchAgent plist for SPM/standalone execution
        return FileManager.default.fileExists(atPath: launchAgentPlistURL.path) || legacyLaunchAgentPlistURLs.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    public static func setEnabled(_ enable: Bool) {
        if enable {
            // Try SMAppService first if inside a bundle
            if Bundle.main.bundleIdentifier != nil {
                try? SMAppService.mainApp.register()
            }

            // Write launch agent plist to guarantee login launch in both SPM and app bundle
            writeLaunchAgentPlist()
        } else {
            if Bundle.main.bundleIdentifier != nil {
                try? SMAppService.mainApp.unregister()
            }
            removeLaunchAgentPlist()
        }
    }

    private static func writeLaunchAgentPlist() {
        guard let execPath = Bundle.main.executablePath ?? CommandLine.arguments.first else { return }
        let resolvedPath = (execPath as NSString).resolvingSymlinksInPath

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(launchAgentLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(resolvedPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
            <key>ProcessType</key>
            <string>Interactive</string>
        </dict>
        </plist>
        """

        let fileManager = FileManager.default
        let launchAgentsDir = launchAgentPlistURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
        try? plistContent.write(to: launchAgentPlistURL, atomically: true, encoding: .utf8)
    }

    private static func removeLaunchAgentPlist() {
        try? FileManager.default.removeItem(at: launchAgentPlistURL)
        for url in legacyLaunchAgentPlistURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
