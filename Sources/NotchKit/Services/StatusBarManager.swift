import AppKit
import SwiftUI
import ClipCore
import NetCore
import Combine

@MainActor
public final class StatusBarManager: NSObject {
    public static let shared = StatusBarManager()

    private var clipStatusItem: NSStatusItem?
    private var speedStatusItem: NSStatusItem?

    private var clipPopover: NSPopover?
    private var speedPopover: NSPopover?

    private var cancellables = Set<AnyCancellable>()
    private var clipViewModel: ClipBarViewModel?
    private var speedViewModel: SpeedMeterViewModel?

    public func setup(clipViewModel: ClipBarViewModel, speedViewModel: SpeedMeterViewModel) {
        self.clipViewModel = clipViewModel
        self.speedViewModel = speedViewModel

        setupClipPopover(viewModel: clipViewModel)
        setupSpeedPopover(speedVM: speedViewModel, clipVM: clipViewModel)

        setupClipStatusItem()
        setupSpeedStatusItem()

        observeSettings()
        observeSpeedUpdates()
    }

    // MARK: - Popovers

    private func setupClipPopover(viewModel: ClipBarViewModel) {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 440, height: 590)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: PopoverRootView(viewModel: viewModel))
        self.clipPopover = popover
    }

    private func setupSpeedPopover(speedVM: SpeedMeterViewModel, clipVM: ClipBarViewModel) {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 530)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: SpeedMeterPopoverView(speedVM: speedVM, clipVM: clipVM))
        self.speedPopover = popover
    }

    // MARK: - Status Items

    private func setupClipStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "NotchKit Clips")
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

        if let popover = clipPopover, popover.isShown {
            popover.performClose(nil)
        } else {
            speedPopover?.performClose(nil)
            clipViewModel?.refreshClips()
            clipPopover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    @objc private func handleSpeedButtonClicked() {
        guard let button = speedStatusItem?.button else { return }

        if let popover = speedPopover, popover.isShown {
            popover.performClose(nil)
        } else {
            clipPopover?.performClose(nil)
            speedPopover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApplication.shared.activate(ignoringOtherApps: true)
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
