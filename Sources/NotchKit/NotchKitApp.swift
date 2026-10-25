import SwiftUI
import AppKit
import ClipCore
import NetCore

@main
struct NotchKitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run purely as an accessory menu bar application (no Dock icon)
        NSApplication.shared.setActivationPolicy(.accessory)

        // Start background pasteboard monitoring
        PasteboardService.shared.startMonitoring()

        // Set up rock-solid native AppKit status items for Clipboard & Speed Meter
        StatusBarManager.shared.setup(
            clipViewModel: ClipBarViewModel.shared,
            speedViewModel: SpeedMeterViewModel.shared
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        PasteboardService.shared.stopMonitoring()
        NetworkSpeedMonitor.shared.stopMonitoring()
    }
}
