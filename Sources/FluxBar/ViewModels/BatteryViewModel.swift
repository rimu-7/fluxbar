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
    @Published public var helperNeedsUpdate: Bool = false
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
            // A saved preference alone cannot enforce a charge limit.
            self.isLimiterEnabled = false
        }

        self.helperNeedsUpdate = PowerHelperManager.needsUpdate
        persistSettings()
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
        guard !isAuthorizingHelper else { return }
        let clamped = normalized(newLimit)
        guard clamped != chargeLimit else { return }
        chargeLimit = clamped
        scheduleSave(persistToSettings: true)
    }

    public func setLimiterEnabled(_ enabled: Bool) {
        guard !isAuthorizingHelper else { return }
        guard method != .unavailable else {
            statusMessage = "Charge limits are not supported by this Mac’s hardware and macOS combination."
            return
        }
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
        guard method != .unavailable else {
            isLimiterEnabled = false
            persistSettings()
            statusMessage = "Charge limits are not supported by this Mac’s hardware and macOS combination."
            return
        }
        let config = ChargeLimitConfig(isEnabled: isLimiterEnabled, limit: chargeLimit, hysteresis: hysteresis)

        if persistToSettings { persistSettings() }

        if method == .macOS {
            do {
                let applied = try NativeChargeLimit.set(config.isEnabled ? config.limit : 100)
                if config.isEnabled && applied != chargeLimit { chargeLimit = applied }
                statusMessage = applied < 100
                    ? "Charging will hold at \(applied)% (macOS charge limit)."
                    : "Limit off. Charging normally to 100%."
            } catch {
                if let current = NativeChargeLimit.currentLimit() {
                    isLimiterEnabled = current < 100
                    if current < 100 { chargeLimit = current }
                    persistSettings()
                }
                statusMessage = error.localizedDescription
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.refresh() }
            return
        }

        isHelperInstalled = PowerHelperManager.isInstalled
        helperNeedsUpdate = PowerHelperManager.needsUpdate
        if !isHelperInstalled || helperNeedsUpdate || !PowerHelperManager.canWriteConfig {
            if config.isEnabled || isHelperInstalled {
                // DMG installs and standard-user accounts use the same graphical setup path.
                authorizeHelper()
            } else {
                statusMessage = "Limit off. Charging normally."
            }
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
        helperNeedsUpdate = PowerHelperManager.needsUpdate
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
        guard method == .helper, !isAuthorizingHelper else { return }
        pendingSave?.cancel()
        pendingSave = nil
        isAuthorizingHelper = true
        statusMessage = "Waiting for administrator approval…"
        let previouslyEnabled = PowerHelperManager.isInstalled ? (ChargeLimitConfig.load()?.isEnabled ?? false) : false
        let config = ChargeLimitConfig(isEnabled: isHelperInstalled ? isLimiterEnabled : true, limit: chargeLimit, hysteresis: hysteresis)

        Task { @MainActor in
            do {
                try await PowerHelperManager.installWithAdminPrompt(config: config)
                isLimiterEnabled = config.isEnabled
                statusMessage = config.isEnabled
                    ? "Battery controls are ready. Charging will hold at \(config.limit)%, even when FluxBar is closed."
                    : "Battery controls are ready. The charge limit is off."
            } catch {
                // Restore actual state after a cancelled or failed setup, rather than leaving
                // an enabled-looking toggle for a limit that is not being enforced.
                isLimiterEnabled = previouslyEnabled
                statusMessage = error.localizedDescription
            }
            persistSettings()
            isAuthorizingHelper = false
            refresh()
        }
    }

    public func uninstallHelper() {
        guard !isAuthorizingHelper else { return }
        pendingSave?.cancel()
        pendingSave = nil
        isAuthorizingHelper = true
        Task { @MainActor in
            do {
                try await PowerHelperManager.uninstallWithAdminPrompt()
                if method == .helper {
                    isLimiterEnabled = false
                    persistSettings()
                }
                statusMessage = method == .macOS ? "Old battery helper removed." : "Battery helper removed. Normal charging restored."
            } catch {
                statusMessage = error.localizedDescription
            }
            isAuthorizingHelper = false
            refresh()
        }
    }

    private func persistSettings() {
        var settings = ClipBarViewModel.shared.settings
        guard settings.batteryChargeLimit != chargeLimit || settings.isBatteryLimiterEnabled != isLimiterEnabled else { return }
        settings.batteryChargeLimit = chargeLimit
        settings.isBatteryLimiterEnabled = isLimiterEnabled
        ClipBarViewModel.shared.updateSettings(settings)
    }
}
