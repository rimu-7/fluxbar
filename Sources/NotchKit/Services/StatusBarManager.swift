import AppKit
import SwiftUI
import ClipCore
import NetCore
import PowerCore
import Combine

@MainActor
public final class StatusBarManager: NSObject {
    public static let shared = StatusBarManager()

    private var clipStatusItem: NSStatusItem?
    private var speedStatusItem: NSStatusItem?

    private var unifiedPopover: NSPopover?
    public var selectedTab: NotchKitTab = .clipboard

    private var cancellables = Set<AnyCancellable>()
    private var clipViewModel: ClipBarViewModel?
    private var speedViewModel: SpeedMeterViewModel?
    private var batteryViewModel: BatteryViewModel?
    private var keyMonitor: Any?

    public func setup(
        clipViewModel: ClipBarViewModel,
        speedViewModel: SpeedMeterViewModel,
        batteryViewModel: BatteryViewModel
    ) {
        self.clipViewModel = clipViewModel
        self.speedViewModel = speedViewModel
        self.batteryViewModel = batteryViewModel

        setupUnifiedPopover()

        setupClipStatusItem()
        setupSpeedStatusItem()

        observeSettings()
        observeSpeedUpdates()
        setupEscapeKeyMonitor()
    }

    // MARK: - Unified Popover

    private func setupUnifiedPopover() {
        guard let clipVM = clipViewModel,
              let speedVM = speedViewModel,
              let batteryVM = batteryViewModel else { return }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 440, height: 600)
        popover.behavior = .transient
        popover.animates = true

        let rootView = NotchKitMainPopoverView(
            clipVM: clipVM,
            speedVM: speedVM,
            batteryVM: batteryVM,
            selectedTab: Binding(
                get: { [weak self] in self?.selectedTab ?? .clipboard },
                set: { [weak self] in self?.selectedTab = $0 }
            )
        )
        popover.contentViewController = NSHostingController(rootView: rootView)
        self.unifiedPopover = popover
    }

    public func closePopover() {
        unifiedPopover?.performClose(nil)
    }

    // MARK: - Status Items (Only Copy Icon & Speed Meter in Menu Bar)

    private func setupClipStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            // High-precision macOS Copy icon as requested
            let copyImage = NSImage(systemSymbolName: "doc.on.doc.fill", accessibilityDescription: "NotchKit Clipboard")
                ?? NSImage(systemSymbolName: "doc.on.clipboard.fill", accessibilityDescription: "NotchKit Clipboard")
            button.image = copyImage
            button.target = self
            button.action = #selector(handleClipButtonClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        item.isVisible = clipViewModel?.settings.isClipboardEnabled ?? true
        self.clipStatusItem = item
    }

    private func setupSpeedStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = "↓ 0 B/s  ↑ 0 B/s"
            button.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .medium)
            button.target = self
            button.action = #selector(handleSpeedButtonClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        item.isVisible = speedViewModel?.isSpeedMeterEnabled ?? true
        self.speedStatusItem = item
    }

    // MARK: - Button Actions

    @objc private func handleClipButtonClicked() {
        guard let button = clipStatusItem?.button else { return }

        if let popover = unifiedPopover, popover.isShown && selectedTab == .clipboard {
            popover.performClose(nil)
        } else {
            selectedTab = .clipboard
            clipViewModel?.refreshClips()
            unifiedPopover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    @objc private func handleSpeedButtonClicked() {
        guard let button = speedStatusItem?.button else { return }

        if let popover = unifiedPopover, popover.isShown && selectedTab == .speedMeter {
            popover.performClose(nil)
        } else {
            selectedTab = .speedMeter
            unifiedPopover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Escape Key to Close

    private func setupEscapeKeyMonitor() {
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { // ESC key
                    if let popover = self?.unifiedPopover, popover.isShown {
                        popover.performClose(nil)
                        return nil
                    }
                }
                return event
            }
        }
    }

    // MARK: - Observers

    private func observeSpeedUpdates() {
        guard let speedVM = speedViewModel else { return }
        speedVM.$currentSpeed
            .receive(on: RunLoop.main)
            .sink { [weak self] newSpeed in
                self?.updateSpeedTitle(newSpeed.menuBarLabel)
            }
            .store(in: &cancellables)
    }

    private func updateSpeedTitle(_ title: String) {
        guard let button = speedStatusItem?.button else { return }
        button.title = title
        button.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .medium)
    }

    private func observeSettings() {
        guard let clipVM = clipViewModel else { return }
        clipVM.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] settings in
                self?.clipStatusItem?.isVisible = settings.isClipboardEnabled
                self?.speedStatusItem?.isVisible = settings.isSpeedMeterEnabled
            }
            .store(in: &cancellables)
    }
}
