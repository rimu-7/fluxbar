import Foundation
import SwiftUI
import Combine
import PowerCore
import ClipCore

@MainActor
public final class BatteryViewModel: ObservableObject {
    public static let shared = BatteryViewModel()

    @Published public var telemetry: BatteryTelemetry
    @Published public var chargeLimit: Int
    @Published public var isLimiterEnabled: Bool
    @Published public var isBypassActive: Bool
    @Published public var isHelperInstalled: Bool
    @Published public var isAuthorizingHelper: Bool = false
    @Published public var statusMessage: String?

    public let availablePresets = PowerSettings.availablePresets

    private let limiter: ChargeLimiter
    private let monitor: BatteryMonitor
    private let smcService: SMCService
    private var cancellables = Set<AnyCancellable>()

    public init(
        limiter: ChargeLimiter = .shared,
        monitor: BatteryMonitor = .shared,
        smcService: SMCService = .shared
    ) {
        self.limiter = limiter
        self.monitor = monitor
        self.smcService = smcService

        let initialTelemetry = monitor.currentTelemetry
        self.telemetry = initialTelemetry
        self.chargeLimit = limiter.chargeLimit
        self.isLimiterEnabled = limiter.isLimiterEnabled
        self.isBypassActive = limiter.isAdapterBypassActive
        self.isHelperInstalled = smcService.isHelperInstalled

        setupSubscriptions()
        monitor.startMonitoring()
    }

    private func setupSubscriptions() {
        // Observe live telemetry
        monitor.telemetryPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] newTelemetry in
                guard let self = self else { return }
                self.telemetry = newTelemetry
                self.isBypassActive = self.limiter.isAdapterBypassActive || (newTelemetry.isPluggedIn && !newTelemetry.isCharging && newTelemetry.percentage >= self.chargeLimit)
            }
            .store(in: &cancellables)

        // Observe limiter state changes
        NotificationCenter.default.publisher(for: .batteryChargeLimiterStateDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.isBypassActive = self.limiter.isAdapterBypassActive
                self.isHelperInstalled = self.smcService.isHelperInstalled
            }
            .store(in: &cancellables)

        // Observe limit reached notifications
        NotificationCenter.default.publisher(for: .batteryChargeLimitReached)
            .receive(on: RunLoop.main)
            .sink { [weak self] notif in
                guard let self = self else { return }
                let limit = notif.userInfo?["limit"] as? Int ?? self.chargeLimit
                self.statusMessage = "Limit reached (\(limit)%). Running directly from Power Adapter."
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    public func setChargeLimit(_ newLimit: Int) {
        let clamped = max(50, min(100, newLimit))
        self.chargeLimit = clamped
        limiter.setChargeLimit(clamped)

        // Persist to AppSettings
        var currentSettings = ClipBarViewModel.shared.settings
        currentSettings.batteryChargeLimit = clamped
        ClipBarViewModel.shared.updateSettings(currentSettings)
    }

    public func setLimiterEnabled(_ enabled: Bool) {
        self.isLimiterEnabled = enabled
        limiter.setEnabled(enabled)

        // Persist to AppSettings
        var currentSettings = ClipBarViewModel.shared.settings
        currentSettings.isBatteryLimiterEnabled = enabled
        ClipBarViewModel.shared.updateSettings(currentSettings)
    }

    public func refresh() {
        monitor.refresh()
        self.isHelperInstalled = smcService.isHelperInstalled
    }

    public func authorizeHelper() {
        guard !isAuthorizingHelper else { return }
        isAuthorizingHelper = true
        statusMessage = "Requesting authorization..."

        Task {
            let success = await PowerHelperManager.requestHelperInstallation()
            await MainActor.run {
                self.isAuthorizingHelper = false
                self.isHelperInstalled = self.smcService.isHelperInstalled || success
                if success {
                    self.statusMessage = "Hardware SMC control authorized successfully!"
                    self.limiter.evaluateCurrentState(telemetry: self.telemetry)
                } else {
                    self.statusMessage = "Authorization was cancelled or failed."
                }
            }
        }
    }
}
