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

        // Daily, silent update check (only interrupts when a new version exists).
        GitHubUpdater.shared.start()

        // `flux update` asks us to quit so it can replace the app (it relaunches us afterwards).
        DistributedNotificationCenter.default().addObserver(
            forName: UpdateEngine.quitForUpdateNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
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
