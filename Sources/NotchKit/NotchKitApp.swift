import SwiftUI
import AppKit
import ClipCore
import NetCore

@main
struct NotchKitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var clipViewModel = ClipBarViewModel()
    @StateObject private var speedViewModel = SpeedMeterViewModel.shared

    var body: some Scene {
        // Tool 1: Clipboard History Manager Extra
        MenuBarExtra("NotchKit Clips", systemImage: "paperclip", isInserted: $clipViewModel.settings.isClipboardEnabled) {
            PopoverRootView(viewModel: clipViewModel)
        }
        .menuBarExtraStyle(.window)

        // Tool 2: Internet Speed Meter Extra
        MenuBarExtra(isInserted: $speedViewModel.isSpeedMeterEnabled) {
            SpeedMeterPopoverView(speedVM: speedViewModel, clipVM: clipViewModel)
        } label: {
            SpeedMeterMenuBarLabel(viewModel: speedViewModel)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon, accessory menu-bar only
        NSApplication.shared.setActivationPolicy(.accessory)
        // Start background pasteboard watcher
        PasteboardService.shared.startMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        PasteboardService.shared.stopMonitoring()
        NetworkSpeedMonitor.shared.stopMonitoring()
    }
}
