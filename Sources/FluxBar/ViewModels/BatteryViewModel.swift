import Foundation
import SwiftUI
import Combine
import PowerCore
import ClipCore

/// Battery tab state. The app never writes the SMC itself. Depending on the Mac, the limit is either
/// the macOS charge limit (macOS 27+, set directly) or saved for the root helper (`com.fluxbar.powerd`)
/// to enforce. Both keep working while FluxBar is quit.
@MainActor
public final class BatteryViewModel: ObservableObject {
    public static let shared = BatteryViewModel()

    @Published public var telemetry: BatteryTelemetry
    @Published public var chargeLimit: Int
    @Published public var isLimiterEnabled: Bool
    @Published public var isBypassActive: Bool = false
    @Published public var isHelperInstalled: Bool
    @Published public var isAuthorizingHelper: Bool = false
    @Published public var statusMessage: String?

    /// How this Mac enforces the limit. Decided once at launch.
    public let method: ChargeLimitMethod
    public var minimumLimit: Int { method.minimumLimit }
    public var availablePresets: [Int] {
        method == .macOS ? NativeChargeLimit.availableLimits : PowerSettings.availablePresets
    }

    private let monitor: BatteryMonitor
    private var cancellables = Set<AnyCancellable>()
    private var pendingSave: Task<Void, Never>?
    private var hysteresis: Int = ChargeLimitConfig.default.hysteresis

    public init(monitor: BatteryMonitor = .shared) {
        self.monitor = monitor
        self.telemetry = monitor.currentTelemetry
        self.isHelperInstalled = PowerHelperManager.isInstalled
        let method = ChargeLimitMethod.current
        self.method = method
        let settings = ClipBarViewModel.shared.settings

        if method == .macOS {
            // macOS owns the setting (it can also change in System Settings).
            let native = NativeChargeLimit.currentLimit() ?? 100
            self.isLimiterEnabled = native < 100
            self.chargeLimit = native < 100
                ? native
                : NativeChargeLimit.nearestSupported(settings.batteryChargeLimit > 0 ? settings.batteryChargeLimit : 80)
        } else if PowerHelperManager.isInstalled, let config = ChargeLimitConfig.load() {
            // The helper's settings are the source of truth (they may have been changed from the CLI).
            self.chargeLimit = config.limit
            self.isLimiterEnabled = config.isEnabled
            self.hysteresis = config.hysteresis
        } else {
            self.chargeLimit = ChargeLimitConfig.clampLimit(settings.batteryChargeLimit > 0 ? settings.batteryChargeLimit : 80)
            self.isLimiterEnabled = settings.isBatteryLimiterEnabled
        }

        setupSubscriptions()
        monitor.startMonitoring()
        updateBypassState()
    }

    private func setupSubscriptions() {
        monitor.telemetryPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] newTelemetry in
                guard let self else { return }
                if self.telemetry != newTelemetry { self.telemetry = newTelemetry }
                self.updateBypassState()
            }
            .store(in: &cancellables)

        // Keep in sync with the toggle in Settings.
        ClipBarViewModel.shared.$settings
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] settings in
                guard let self else { return }
                let limit = self.normalized(settings.batteryChargeLimit)
                if settings.isBatteryLimiterEnabled != self.isLimiterEnabled || limit != self.chargeLimit {
                    self.isLimiterEnabled = settings.isBatteryLimiterEnabled
                    self.chargeLimit = limit
                    self.scheduleSave(persistToSettings: false)
                }
            }
            .store(in: &cancellables)
    }

    /// Clamps (and on macOS-limit Macs, snaps) a limit to what this Mac supports.
    private func normalized(_ limit: Int) -> Int {
        method == .macOS ? NativeChargeLimit.nearestSupported(limit) : ChargeLimitConfig.clampLimit(limit)
    }

    private func updateBypassState() {
        let held: Bool
        if method == .helper, isHelperInstalled, let status = PowerHelperManager.daemonStatus() {
            held = status.isChargingInhibited && telemetry.isPluggedIn
        } else {
            held = isLimiterEnabled && telemetry.isPluggedIn && !telemetry.isCharging
                && telemetry.percentage >= chargeLimit - hysteresis
        }
        if held != isBypassActive { isBypassActive = held }
    }

    // MARK: - Actions

    public func setChargeLimit(_ newLimit: Int) {
        let clamped = normalized(newLimit)
        guard clamped != chargeLimit else { return }
        chargeLimit = clamped
        scheduleSave(persistToSettings: true)
    }

    public func setLimiterEnabled(_ enabled: Bool) {
        guard enabled != isLimiterEnabled else { return }
        isLimiterEnabled = enabled
        scheduleSave(persistToSettings: true)
    }

    /// Debounced so dragging the slider writes once, not 50 times.
    private func scheduleSave(persistToSettings: Bool) {
        pendingSave?.cancel()
        pendingSave = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, !Task.isCancelled else { return }
            self.pendingSave = nil
            self.save(persistToSettings: persistToSettings)
        }
    }

    private func save(persistToSettings: Bool) {
        let config = ChargeLimitConfig(isEnabled: isLimiterEnabled, limit: chargeLimit, hysteresis: hysteresis)

        if persistToSettings {
            var settings = ClipBarViewModel.shared.settings
            if settings.batteryChargeLimit != config.limit || settings.isBatteryLimiterEnabled != config.isEnabled {
                settings.batteryChargeLimit = config.limit
                settings.isBatteryLimiterEnabled = config.isEnabled
                ClipBarViewModel.shared.updateSettings(settings)
            }
        }

        if method == .macOS {
            do {
                let applied = try NativeChargeLimit.set(config.isEnabled ? config.limit : 100)
                if config.isEnabled && applied != chargeLimit { chargeLimit = applied }
                statusMessage = applied < 100
                    ? "Charging will hold at \(applied)% (macOS charge limit)."
                    : "Limit off. Charging normally to 100%."
            } catch {
                statusMessage = error.localizedDescription
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.refresh() }
            return
        }

        isHelperInstalled = PowerHelperManager.isInstalled
        guard isHelperInstalled else {
            statusMessage = "Install the battery helper to enforce this limit."
            return
        }
        do {
            try PowerHelperManager.save(config)
            statusMessage = config.isEnabled && config.limit < 100
                ? "Charging will hold at \(config.limit)%."
                : "Limiter off. Charging normally to 100%."
            // The helper reacts within a second; refresh shortly after to show its decision.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.refresh() }
        } catch {
            statusMessage = "Couldn't save the limit: \(error.localizedDescription)"
        }
    }

    public func refresh() {
        monitor.refresh()
        isHelperInstalled = PowerHelperManager.isInstalled
        if method == .macOS, pendingSave == nil, let native = NativeChargeLimit.currentLimit() {
            // Pick up changes made in System Settings.
            let enabled = native < 100
            if enabled != isLimiterEnabled { isLimiterEnabled = enabled }
            if enabled && native != chargeLimit { chargeLimit = native }
        }
        updateBypassState()
    }

    /// Deep battery details are only read while the popover is open.
    public func setPopoverVisible(_ visible: Bool) {
        monitor.setPopoverVisible(visible)
        if visible { refresh() }
    }

    public func authorizeHelper() {
        guard !isAuthorizingHelper else { return }
        isAuthorizingHelper = true
        statusMessage = "Waiting for administrator approval…"
        let config = ChargeLimitConfig(isEnabled: isLimiterEnabled, limit: chargeLimit, hysteresis: hysteresis)

        Task { @MainActor in
            do {
                try await PowerHelperManager.installWithAdminPrompt(config: config)
                statusMessage = "Battery helper installed. Limit is now enforced, even when FluxBar is closed."
            } catch {
                statusMessage = error.localizedDescription
            }
            isAuthorizingHelper = false
            refresh()
        }
    }

    public func uninstallHelper() {
        guard !isAuthorizingHelper else { return }
        isAuthorizingHelper = true
        Task { @MainActor in
            do {
                try await PowerHelperManager.uninstallWithAdminPrompt()
                statusMessage = method == .macOS ? "Old battery helper removed." : "Battery helper removed. Normal charging restored."
            } catch {
                statusMessage = error.localizedDescription
            }
            isAuthorizingHelper = false
            refresh()
        }
    }
}
