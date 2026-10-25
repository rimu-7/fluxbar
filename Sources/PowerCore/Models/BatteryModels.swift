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

/// Represents external peripherals (iPhone, Watch, AirPods, accessories) drawing reverse charging power from MacBook
public struct ConnectedAccessoryPower: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(portIndex)-\(deviceName)" }
    public var portIndex: Int
    public var portName: String
    public var deviceName: String
    public var isChargingFromMac: Bool
    public var batteryLevel: Int?
    public var estimatedOutputWatts: Double

    public init(
        portIndex: Int,
        portName: String = "USB-C Port",
        deviceName: String = "USB Device",
        isChargingFromMac: Bool = true,
        batteryLevel: Int? = nil,
        estimatedOutputWatts: Double = 7.5
    ) {
        self.portIndex = portIndex
        self.portName = portName
        self.deviceName = deviceName
        self.isChargingFromMac = isChargingFromMac
        self.batteryLevel = batteryLevel
        self.estimatedOutputWatts = estimatedOutputWatts
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

    // Detailed Charger Hardware Telemetry
    public var adapterVoltage: Double?      // e.g. 20.0 V
    public var adapterAmperage: Double?     // e.g. 4.99 A
    public var inputPowerWatts: Double?     // e.g. 72.0 W (live active negotiated power flow)
    public var inputVoltage: Double?        // e.g. 20.0 V
    public var inputCurrentAmps: Double?    // e.g. 3.6 A
    public var activeProfileIndex: Int?     // e.g. 4 (index of selected USB-PD profile)
    public var chargerPortIndex: Int?       // e.g. 3 (which USB-C port charger is connected to)
    public var adapterProfiles: [String]    // e.g. ["5V @ 3A", "9V @ 3A", "15V @ 3A", "20V @ 5A"]
    public var connectedAccessories: [ConnectedAccessoryPower] // External devices being charged by Mac

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
        timestamp: Date = Date(),
        adapterVoltage: Double? = nil,
        adapterAmperage: Double? = nil,
        inputPowerWatts: Double? = nil,
        inputVoltage: Double? = nil,
        inputCurrentAmps: Double? = nil,
        activeProfileIndex: Int? = nil,
        chargerPortIndex: Int? = nil,
        adapterProfiles: [String] = [],
        connectedAccessories: [ConnectedAccessoryPower] = []
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
        self.adapterVoltage = adapterVoltage
        self.adapterAmperage = adapterAmperage
        self.inputPowerWatts = inputPowerWatts
        self.inputVoltage = inputVoltage
        self.inputCurrentAmps = inputCurrentAmps
        self.activeProfileIndex = activeProfileIndex
        self.chargerPortIndex = chargerPortIndex
        self.adapterProfiles = adapterProfiles
        self.connectedAccessories = connectedAccessories
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
    /// Lost capacity from original factory design
    public var degradedCapacity: Int {
        max(0, designCapacity - fullChargeCapacity)
    }

    /// Degradation percentage (0% = brand new, 20% = 80% health)
    public var degradationPercentage: Double {
        max(0.0, min(100.0, 100.0 - healthPercentage))
    }

    /// Standard Apple Silicon rated lifecycle (1000 full recharge cycles)
    public var ratedCycles: Int { 1000 }

    /// Lifecycle remaining percentage based on 1000 cycles
    public var cycleLifeRemainingPercentage: Double {
        max(0.0, min(100.0, (1.0 - (Double(cycleCount) / 1000.0)) * 100.0))
    }

    /// Estimated remaining years of battery life
    public var estimatedYearsRemaining: Double {
        let cyclesLeft = max(0, 1000 - cycleCount)
        return max(0.5, (Double(cyclesLeft) / 180.0 * 10).rounded() / 10.0)
    }

    /// Qualitative battery health classification
    public var healthGrade: String {
        if healthPercentage >= 90 { return "Optimal" }
        if healthPercentage >= 80 { return "Normal (Peak)" }
        if healthPercentage >= 70 { return "Moderate" }
        return "Service Soon"
    }

    /// Thermal state description
    public var thermalStateDescription: String {
        if temperature < 32.0 { return "Cool & Normal" }
        if temperature < 38.0 { return "Optimal" }
        if temperature < 44.0 { return "Warm" }
        return "Hot"
    }

    /// Voltage formatted in Volts (e.g. 13.19 V)
    public var voltageInVolts: Double {
        (Double(voltage) / 100.0).rounded() / 10.0
    }
}

/// User configurable settings for battery charge limiting
public struct PowerSettings: Codable, Sendable, Equatable {
    public var isLimiterEnabled: Bool
    public var chargeLimit: Int
    public var hysteresisPercentage: Int
    public var notifyOnLimitReached: Bool
    public var isAdapterBypassActive: Bool

    public static let availablePresets: [Int] = [50, 70, 75, 80, 85, 90, 100]

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
