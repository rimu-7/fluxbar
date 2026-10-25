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

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run purely as an accessory menu bar application (no Dock icon)
        NSApplication.shared.setActivationPolicy(.accessory)

        // Start background pasteboard monitoring
        PasteboardService.shared.startMonitoring()

        // Set up rock-solid native AppKit status items for Clipboard, Speed Meter & Battery Limiter
        StatusBarManager.shared.setup(
            clipViewModel: ClipBarViewModel.shared,
            speedViewModel: SpeedMeterViewModel.shared,
            batteryViewModel: BatteryViewModel.shared
        )

        print("=======================================================")
        print("  🚀 FluxBar is running successfully!")
        print("  • Look at your macOS menu bar (top right) for:")
        print("    1. Copy icon (Clipboard History)")
        print("    2. Speed Meter (Live 2-line ↑/↓ Network Speeds)")
        print("  • Both icons open the unified UI (Clipboard | Battery | Speed).")
        print("  • Press Ctrl+C in this terminal to stop.")
        print("=======================================================")
        fflush(stdout)
    }

    func applicationWillTerminate(_ notification: Notification) {
        PasteboardService.shared.stopMonitoring()
        NetworkSpeedMonitor.shared.stopMonitoring()
        BatteryMonitor.shared.stopMonitoring()
        BandwidthStore.shared.flushToDisk()
    }
}
