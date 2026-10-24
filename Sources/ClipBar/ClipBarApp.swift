import SwiftUI
import AppKit
import ClipCore

@main
struct ClipBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("ClipSuite", systemImage: "paperclip") {
            PopoverRootView()
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
    }
}
