import Foundation

/// Represents the high-level operational charging state of the Mac
public enum ChargingState: String, Codable, Sendable, Equatable {
    /// Actively receiving power to recharge the battery cells
    case charging = "Charging"
    /// AC adapter connected, but battery charging is inhibited (Power Adapter Bypass Mode)
    case bypassed = "Power Adapter Bypass"
    /// Running entirely on internal battery power without AC adapter
    case discharging = "On Battery"
    /// Battery has completed charging to 100%
    case full = "Fully Charged"

    public var iconName: String {
        switch self {
        case .charging:
            return "bolt.batteryblock.fill"
        case .bypassed:
            return "bolt.fill"
        case .discharging:
            return "battery.75"
        case .full:
            return "battery.100.bolt"
        }
    }

    public var statusDescription: String {
        switch self {
        case .charging:
            return "Charging Battery"
        case .bypassed:
            return "Running from Adapter (Battery Idle)"
        case .discharging:
            return "Discharging"
        case .full:
            return "Battery Full"
        }
    }
}

/// Rich snapshot of real-time battery and power hardware telemetry
public struct BatteryTelemetry: Codable, Sendable, Equatable {
    public var percentage: Int
    public var maxCapacity: Int
    public var isCharging: Bool
    public var isPluggedIn: Bool
    public var isFullyCharged: Bool
    public var amperage: Int             // mA (positive = charging, negative = discharging)
    public var voltage: Int              // mV
    public var wattage: Double           // W (computed from V * A or adapter)
    public var cycleCount: Int
    public var designCapacity: Int       // mAh
    public var fullChargeCapacity: Int   // mAh
    public var healthPercentage: Double  // % (fullChargeCapacity / designCapacity * 100)
    public var temperature: Double       // °C
    public var timeRemainingMinutes: Int? // minutes to full or empty
    public var powerSource: String       // "Power Adapter" or "Battery"
    public var adapterWatts: Int?        // e.g. 100W, 67W, 30W
    public var adapterName: String?      // e.g. "pd charger", "Apple 140W USB-C"
    public var chargingState: ChargingState
    public var isBypassed: Bool          // True when AC connected and charging inhibited
    public var timestamp: Date

    public init(
        percentage: Int = 100,
        maxCapacity: Int = 100,
        isCharging: Bool = false,
        isPluggedIn: Bool = true,
        isFullyCharged: Bool = false,
        amperage: Int = 0,
        voltage: Int = 12000,
        wattage: Double = 0.0,
        cycleCount: Int = 0,
        designCapacity: Int = 5000,
        fullChargeCapacity: Int = 5000,
        healthPercentage: Double = 100.0,
        temperature: Double = 28.0,
        timeRemainingMinutes: Int? = nil,
        powerSource: String = "Power Adapter",
        adapterWatts: Int? = nil,
        adapterName: String? = nil,
        chargingState: ChargingState = .bypassed,
        isBypassed: Bool = false,
        timestamp: Date = Date()
    ) {
        self.percentage = percentage
        self.maxCapacity = maxCapacity
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.isFullyCharged = isFullyCharged
        self.amperage = amperage
        self.voltage = voltage
        self.wattage = wattage
        self.cycleCount = cycleCount
        self.designCapacity = designCapacity
        self.fullChargeCapacity = fullChargeCapacity
        self.healthPercentage = healthPercentage
        self.temperature = temperature
        self.timeRemainingMinutes = timeRemainingMinutes
        self.powerSource = powerSource
        self.adapterWatts = adapterWatts
        self.adapterName = adapterName
        self.chargingState = chargingState
        self.isBypassed = isBypassed
        self.timestamp = timestamp
    }

    public static let `default` = BatteryTelemetry()

    /// Formatted time string: e.g. "32m to full" or "4h 15m remaining"
    public var formattedRemainingTime: String {
        guard let minutes = timeRemainingMinutes, minutes > 0, minutes < 65535 else {
            if isBypassed {
                return "AC Power (Bypass Active)"
            }
            if isPluggedIn && isFullyCharged {
                return "On AC Power"
            }
            return isPluggedIn ? "Calculating..." : "On Battery"
        }

        let hours = minutes / 60
        let mins = minutes % 60
        if isCharging {
            if hours > 0 {
                return "\(hours)h \(mins)m until full"
            } else {
                return "\(mins)m until full"
            }
        } else if !isPluggedIn {
            if hours > 0 {
                return "\(hours)h \(mins)m remaining"
            } else {
                return "\(mins)m remaining"
            }
        } else {
            return "AC Power (Bypass Active)"
        }
    }

    /// Dynamic SF Symbol for menu bar representation
    public var menuBarSymbol: String {
        if isBypassed {
            return "bolt.shield.fill"
        }
        if isCharging {
            return "bolt.batteryblock.fill"
        }
        if isPluggedIn {
            return "powerplug.fill"
        }

        if percentage >= 95 {
            return "battery.100"
        } else if percentage >= 70 {
            return "battery.75"
        } else if percentage >= 45 {
            return "battery.50"
        } else if percentage >= 20 {
            return "battery.25"
        } else {
            return "battery.0"
        }
    }

    /// Formatted menu bar text
    public var menuBarTitle: String {
        if isBypassed {
            return "⚡️ \(percentage)% [AC]"
        } else if isCharging {
            return "⚡️ \(percentage)%"
        } else if isPluggedIn {
            return "🔌 \(percentage)%"
        } else {
            return "\(percentage)%"
        }
    }
}

/// User configurable settings for battery charge limiting
public struct PowerSettings: Codable, Sendable, Equatable {
    public var isLimiterEnabled: Bool
    public var chargeLimit: Int
    public var hysteresisPercentage: Int
    public var notifyOnLimitReached: Bool
    public var isAdapterBypassActive: Bool

    public static let availablePresets: [Int] = [70, 75, 80, 85, 90, 100]

    public init(
        isLimiterEnabled: Bool = true,
        chargeLimit: Int = 80,
        hysteresisPercentage: Int = 2,
        notifyOnLimitReached: Bool = true,
        isAdapterBypassActive: Bool = false
    ) {
        self.isLimiterEnabled = isLimiterEnabled
        self.chargeLimit = chargeLimit
        self.hysteresisPercentage = hysteresisPercentage
        self.notifyOnLimitReached = notifyOnLimitReached
        self.isAdapterBypassActive = isAdapterBypassActive
    }

    public static let `default` = PowerSettings()
}
