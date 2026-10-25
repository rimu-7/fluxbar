import Foundation
import Combine

public extension Notification.Name {
    static let batteryChargeLimiterStateDidChange = Notification.Name("com.notchkit.powercore.stateDidChange")
    static let batteryChargeLimitReached = Notification.Name("com.notchkit.powercore.limitReached")
}

/// Dynamic charge limiter engine controlling battery charging thresholds and adapter bypass
public final class ChargeLimiter: @unchecked Sendable {
    public static let shared = ChargeLimiter()

    public private(set) var isLimiterEnabled: Bool
    public private(set) var chargeLimit: Int
    public private(set) var hysteresis: Int
    public private(set) var isAdapterBypassActive: Bool

    private let smcService: SMCService
    private let monitor: BatteryMonitor
    private var cancellables = Set<AnyCancellable>()
    private let lock = NSRecursiveLock()

    public init(
        smcService: SMCService = .shared,
        monitor: BatteryMonitor = .shared,
        isLimiterEnabled: Bool = true,
        chargeLimit: Int = 80,
        hysteresis: Int = 2
    ) {
        self.smcService = smcService
        self.monitor = monitor
        self.isLimiterEnabled = isLimiterEnabled
        self.chargeLimit = chargeLimit
        self.hysteresis = hysteresis
        self.isAdapterBypassActive = false

        setupTelemetryObservation()
    }

    // MARK: - Configuration Updates

    public func configure(isEnabled: Bool, limit: Int, hysteresis: Int = 2) {
        lock.lock()
        defer { lock.unlock() }

        self.isLimiterEnabled = isEnabled
        self.chargeLimit = max(50, min(100, limit))
        self.hysteresis = max(1, min(5, hysteresis))

        evaluateCurrentStateUnlocked(telemetry: monitor.currentTelemetry)
    }

    public func setChargeLimit(_ limit: Int) {
        configure(isEnabled: isLimiterEnabled, limit: limit, hysteresis: hysteresis)
    }

    public func setEnabled(_ enabled: Bool) {
        configure(isEnabled: enabled, limit: chargeLimit, hysteresis: hysteresis)
    }

    // MARK: - Telemetry Observation & Hysteresis Evaluation

    private func setupTelemetryObservation() {
        monitor.telemetryPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] telemetry in
                self?.evaluateCurrentState(telemetry: telemetry)
            }
            .store(in: &cancellables)
    }

    public func evaluateCurrentState(telemetry: BatteryTelemetry) {
        lock.lock()
        defer { lock.unlock() }
        evaluateCurrentStateUnlocked(telemetry: telemetry)
    }

    private func evaluateCurrentStateUnlocked(telemetry: BatteryTelemetry) {
        guard isLimiterEnabled && chargeLimit < 100 else {
            // Limiter disabled or set to 100% -> resume full normal charging
            if isAdapterBypassActive {
                isAdapterBypassActive = false
                smcService.setChargingInhibited(false, limitPercentage: 100)
                NotificationCenter.default.post(name: .batteryChargeLimiterStateDidChange, object: nil)
            }
            return
        }

        // Only enforce limits while connected to AC power
        guard telemetry.isPluggedIn else {
            if isAdapterBypassActive {
                isAdapterBypassActive = false
                NotificationCenter.default.post(name: .batteryChargeLimiterStateDidChange, object: nil)
            }
            return
        }

        let currentPercent = telemetry.percentage

        if currentPercent >= chargeLimit {
            // Reached or exceeded target limit -> ENGAGE ADAPTER BYPASS
            if !isAdapterBypassActive {
                isAdapterBypassActive = true
                smcService.setChargingInhibited(true, limitPercentage: chargeLimit)
                NotificationCenter.default.post(name: .batteryChargeLimiterStateDidChange, object: nil)
                NotificationCenter.default.post(
                    name: .batteryChargeLimitReached,
                    object: nil,
                    userInfo: ["limit": chargeLimit, "percentage": currentPercent]
                )
            }
        } else if currentPercent <= (chargeLimit - hysteresis) {
            // Dropped below hysteresis band -> RESUME CHARGING
            if isAdapterBypassActive {
                isAdapterBypassActive = false
                smcService.setChargingInhibited(false, limitPercentage: chargeLimit)
                NotificationCenter.default.post(name: .batteryChargeLimiterStateDidChange, object: nil)
            }
        }
    }
}
