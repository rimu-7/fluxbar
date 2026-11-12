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
        // Exercise the actual distributed executable without starting monitors, changing
        // login items or installing a privileged helper. Used after copying out of a DMG.
        if CommandLine.arguments.contains("--check-installation") {
            do {
                try AppInstallation.checkBundle()
                print("FluxBar app bundle is complete.")
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }

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

        if AppInstallation.explainDiskImageIfNeeded() { return }

        LaunchAtLoginHelper.migrateLegacyEntries()
        PasteboardService.shared.startMonitoring()

        StatusBarManager.shared.setup(
            clipViewModel: ClipBarViewModel.shared,
            speedViewModel: SpeedMeterViewModel.shared,
            batteryViewModel: BatteryViewModel.shared
        )

        let firstInstalledLaunch = Bundle.main.bundleURL.pathExtension == "app"
            && !UserDefaults.standard.bool(forKey: "installation.didShowMenuBar")
        if firstInstalledLaunch { UserDefaults.standard.set(true, forKey: "installation.didShowMenuBar") }
        if ProcessInfo.processInfo.arguments.contains("--preview") || firstInstalledLaunch {
            DispatchQueue.main.async {
                StatusBarManager.shared.showPopover()
                if let name = ProcessInfo.processInfo.environment["FLUXBAR_PREVIEW_TAB"],
                   let tab = FluxBarTab(rawValue: name) {
                    StatusBarManager.shared.selectedTab = tab
                }
            }
        }

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
        sender.setActivationPolicy(.accessory)
        StatusBarManager.shared.showPopover()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Never leave the Mac stuck awake after quit (also covers `flux update` relaunches).
        CaffeineManager.shared.releaseAssertion()
        PasteboardService.shared.stopMonitoring()
        NetworkSpeedMonitor.shared.stopMonitoring()
        BatteryMonitor.shared.stopMonitoring()
        BandwidthStore.shared.flushToDisk()
    }
}
