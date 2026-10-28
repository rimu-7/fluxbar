import Foundation
import ServiceManagement

/// Start at Login.
///
/// Inside FluxBar.app this uses the native login item (`SMAppService.mainApp`), which is what
/// System Settings › General › Login Items shows and lets the user switch off.
/// A LaunchAgent plist is only used for unbundled development builds (`swift run`).
public enum LaunchAtLoginHelper {
    private static let launchAgentLabel = "com.fluxbar.FluxBar"

    private static var launchAgentsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    private static var launchAgentPlistURL: URL {
        launchAgentsDir.appendingPathComponent("\(launchAgentLabel).plist")
    }

    private static var legacyLaunchAgentPlistURLs: [URL] {
        [
            launchAgentsDir.appendingPathComponent("com.notchkit.NotchKit.plist"),
            launchAgentsDir.appendingPathComponent("com.clipsuite.ClipBar.plist")
        ]
    }

    private static var isBundledApp: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    public static var isEnabled: Bool {
        if isBundledApp {
            let status = SMAppService.mainApp.status
            return status == .enabled || status == .requiresApproval
        }
        return FileManager.default.fileExists(atPath: launchAgentPlistURL.path)
    }

    public static func setEnabled(_ enable: Bool) {
        if isBundledApp {
            // Remove plists written by older versions, otherwise the app would start twice.
            removeLaunchAgentPlists()
            do {
                if enable {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                if enable { SMAppService.openSystemSettingsLoginItems() }
            }
            return
        }

        if enable {
            writeLaunchAgentPlist()
        } else {
            removeLaunchAgentPlists()
        }
    }

    /// Installed copies only, never a build in Downloads, a DMG or a dev folder.
    private static var isInstalledInApplications: Bool {
        let path = Bundle.main.bundlePath
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix("/Applications/") || path.hasPrefix(home + "/Applications/")
    }

    /// Called once at launch: clean up duplicate login entries from older versions.
    public static func migrateLegacyEntries() {
        guard isBundledApp, isInstalledInApplications else { return }
        let hadPlist = ([launchAgentPlistURL] + legacyLaunchAgentPlistURLs).contains {
            FileManager.default.fileExists(atPath: $0.path)
        }
        guard hadPlist else { return }
        removeLaunchAgentPlists()
        if SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
    }

    private static func writeLaunchAgentPlist() {
        guard let execPath = Bundle.main.executablePath ?? CommandLine.arguments.first else { return }
        let resolvedPath = (execPath as NSString).resolvingSymlinksInPath
        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": [resolvedPath],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive"
        ]
        try? FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
        if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
            try? data.write(to: launchAgentPlistURL, options: .atomic)
        }
    }

    private static func removeLaunchAgentPlists() {
        for url in [launchAgentPlistURL] + legacyLaunchAgentPlistURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
