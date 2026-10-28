import Foundation

/// Charge limit state machine.
///
/// Pure logic: feed it battery telemetry and it decides whether charging should be paused.
/// When the decision changes it calls `actuator`, which in the daemon writes the SMC.
/// It never touches hardware on its own, so the app, CLI and tests can use it safely.
public final class ChargeLimiter: @unchecked Sendable {
    public typealias Actuator = (_ inhibit: Bool, _ limit: Int) -> Bool

    /// Pause charging above this cell temperature (°C)…
    public static let thermalCutoutCelsius: Double = 40.0
    /// …and allow it again once the cells cool below this.
    public static let thermalResumeCelsius: Double = 37.0

    public private(set) var isLimiterEnabled: Bool
    public private(set) var chargeLimit: Int
    public private(set) var hysteresis: Int
    /// True while charging is paused (the Mac runs from the adapter, battery idle).
    public private(set) var isAdapterBypassActive: Bool = false
    public private(set) var isThermalPauseActive: Bool = false
    public private(set) var lastReason: String = "Starting"

    private let actuator: Actuator?
    private let lock = NSLock()

    public init(
        isLimiterEnabled: Bool = true,
        chargeLimit: Int = 80,
        hysteresis: Int = 3,
        actuator: Actuator? = nil
    ) {
        self.isLimiterEnabled = isLimiterEnabled
        self.chargeLimit = ChargeLimitConfig.clampLimit(chargeLimit)
        self.hysteresis = max(1, min(10, hysteresis))
        self.actuator = actuator
    }

    public convenience init(config: ChargeLimitConfig, actuator: Actuator? = nil) {
        self.init(isLimiterEnabled: config.isEnabled, chargeLimit: config.limit, hysteresis: config.hysteresis, actuator: actuator)
    }

    public func configure(isEnabled: Bool, limit: Int, hysteresis: Int = 3) {
        lock.lock()
        isLimiterEnabled = isEnabled
        chargeLimit = ChargeLimitConfig.clampLimit(limit)
        self.hysteresis = max(1, min(10, hysteresis))
        lock.unlock()
    }

    public func configure(_ config: ChargeLimitConfig) {
        configure(isEnabled: config.isEnabled, limit: config.limit, hysteresis: config.hysteresis)
    }

    /// Evaluates telemetry and applies the result.
    /// - Parameter reassert: write the current decision even if it did not change
    ///   (used after wake and at startup, when the SMC may have been reset).
    public func evaluateCurrentState(telemetry: BatteryTelemetry, reassert: Bool = false) {
        lock.lock()
        defer { lock.unlock() }

        let (inhibit, reason) = decide(telemetry: telemetry)
        lastReason = reason
        guard inhibit != isAdapterBypassActive || reassert else { return }

        if let actuator = actuator {
            // Only record the new state if the hardware accepted it, so a failed write is retried next time.
            if actuator(inhibit, chargeLimit) {
                isAdapterBypassActive = inhibit
            }
        } else {
            isAdapterBypassActive = inhibit
        }
    }

    // MARK: - Decision

    private func decide(telemetry: BatteryTelemetry) -> (Bool, String) {
        guard isLimiterEnabled && chargeLimit < 100 else {
            isThermalPauseActive = false
            return (false, "Limiter off")
        }
        guard telemetry.isPluggedIn else {
            isThermalPauseActive = false
            return (false, "On battery")
        }

        if telemetry.temperature >= Self.thermalCutoutCelsius {
            isThermalPauseActive = true
        } else if telemetry.temperature < Self.thermalResumeCelsius {
            isThermalPauseActive = false
        }
        if isThermalPauseActive {
            return (true, "Battery warm, charging paused")
        }

        let percent = telemetry.percentage
        if percent >= chargeLimit {
            return (true, "Holding at \(chargeLimit)%")
        }
        if percent <= chargeLimit - hysteresis {
            return (false, "Charging to \(chargeLimit)%")
        }
        // Inside the hysteresis band: keep doing what we were doing.
        return (isAdapterBypassActive, isAdapterBypassActive ? "Holding at \(chargeLimit)%" : "Charging to \(chargeLimit)%")
    }
}
