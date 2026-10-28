import SwiftUI
import AppKit
import ClipCore
import NetCore
import PowerCore

@main
struct FluxBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only one FluxBar at a time (e.g. login item + manual launch).
        if let bundleID = Bundle.main.bundleIdentifier {
            let me = NSRunningApplication.current
            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: { $0 != me }) {
                NSApp.terminate(nil)
                return
            }
        }

        // Menu bar only: no Dock icon, no app menu.
        NSApp.setActivationPolicy(.accessory)

        LaunchAtLoginHelper.migrateLegacyEntries()
        PasteboardService.shared.startMonitoring()

        StatusBarManager.shared.setup(
            clipViewModel: ClipBarViewModel.shared,
            speedViewModel: SpeedMeterViewModel.shared,
            batteryViewModel: BatteryViewModel.shared
        )
    }

    /// Double-clicking FluxBar in Finder / Launchpad while it's running opens the popover.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        StatusBarManager.shared.showPopover()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        PasteboardService.shared.stopMonitoring()
        NetworkSpeedMonitor.shared.stopMonitoring()
        BatteryMonitor.shared.stopMonitoring()
        BandwidthStore.shared.flushToDisk()
    }
}
