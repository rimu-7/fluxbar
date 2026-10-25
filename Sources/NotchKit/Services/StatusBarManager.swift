import AppKit
import SwiftUI
import ClipCore
import NetCore
import PowerCore
import Combine

@MainActor
public final class StatusBarManager: NSObject, ObservableObject, NSPopoverDelegate {
    public static let shared = StatusBarManager()

    private var clipStatusItem: NSStatusItem?
    private var speedStatusItem: NSStatusItem?

    private var unifiedPopover: NSPopover?
    @Published public var selectedTab: NotchKitTab = .clipboard

    private var cancellables = Set<AnyCancellable>()
    private var clipViewModel: ClipBarViewModel?
    private var speedViewModel: SpeedMeterViewModel?
    private var batteryViewModel: BatteryViewModel?
    private var keyMonitor: Any?

    private var lastRenderedSpeedTitle: String?

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

    // MARK: - Unified Popover Lifecycle

    private func setupUnifiedPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 485, height: 640)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        // Keep contentViewController empty initially to avoid allocating Metal textures at launch
        popover.contentViewController = NSViewController()
        self.unifiedPopover = popover
    }

    private func presentPopover(relativeTo rect: NSRect, of view: NSView, edge: NSRectEdge) {
        guard let popover = unifiedPopover,
              let clipVM = clipViewModel,
              let speedVM = speedViewModel,
              let batteryVM = batteryViewModel else { return }

        // 1. Activate high-frequency telemetry & fetch initial data
        batteryVM.setPopoverVisible(true)
        speedVM.setPopoverVisible(true)
        clipVM.setPopoverVisible(true)

        // 2. Recreate the fresh SwiftUI hierarchy
        let rootView = NotchKitMainPopoverView(
            clipVM: clipVM,
            speedVM: speedVM,
            batteryVM: batteryVM,
            statusManager: self
        )
        popover.contentViewController = NSHostingController(rootView: rootView)

        // 3. Show popover
        popover.show(relativeTo: rect, of: view, preferredEdge: edge)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    public func closePopover() {
        unifiedPopover?.close()
    }

    // MARK: - NSPopoverDelegate (Destroy SwiftUI View Tree on Popover Close)

    public func popoverDidClose(_ notification: Notification) {
        // 1. Pause expensive high-frequency telemetry (USB-PD profiles, deep AppleSmartBattery, 24h charts)
        batteryViewModel?.setPopoverVisible(false)
        speedViewModel?.setPopoverVisible(false)
        clipViewModel?.setPopoverVisible(false)

        // 2. Replace the heavy SwiftUI hierarchy with an empty controller
        // This immediately frees 20-35 MB of Metal backing textures & SwiftUI view graph!
        unifiedPopover?.contentViewController = NSViewController()

        // 3. Reclaim any transient SQLite memory
        DatabaseManager.shared.shrinkMemory()
    }

    // MARK: - Status Items (Only Copy Icon & Speed Meter in Menu Bar)

    private func setupClipStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
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
            let initialTitle = "↓ 0 B/s  ↑ 0 B/s"
            button.title = initialTitle
            lastRenderedSpeedTitle = initialTitle
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

        if let popover = unifiedPopover, popover.isShown {
            let wasClipboard = (selectedTab == .clipboard)
            popover.close()
            if wasClipboard { return }
        }

        selectedTab = .clipboard
        presentPopover(relativeTo: button.bounds, of: button, edge: .minY)
    }

    @objc private func handleSpeedButtonClicked() {
        guard let button = speedStatusItem?.button else { return }

        if let popover = unifiedPopover, popover.isShown {
            let wasSpeed = (selectedTab == .speedMeter)
            popover.close()
            if wasSpeed { return }
        }

        selectedTab = .speedMeter
        presentPopover(relativeTo: button.bounds, of: button, edge: .minY)
    }

    // MARK: - Escape Key to Close

    private func setupEscapeKeyMonitor() {
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { // ESC key
                    if let popover = self?.unifiedPopover, popover.isShown {
                        popover.close()
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

    /// Skips NSStatusItem redraws if the speed string is unchanged.
    /// Eliminates unnecessary WindowServer GPU wakeups and redraw overhead.
    private func updateSpeedTitle(_ title: String) {
        guard title != lastRenderedSpeedTitle else { return }
        lastRenderedSpeedTitle = title

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
