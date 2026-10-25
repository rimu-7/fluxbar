import Foundation
import Combine
import IOKit
import IOKit.ps

/// Real-time monitor querying AppleSmartBattery and IOPowerSources telemetry
public final class BatteryMonitor: @unchecked Sendable {
    public static let shared = BatteryMonitor()

    public let telemetryPublisher: CurrentValueSubject<BatteryTelemetry, Never>
    public var currentTelemetry: BatteryTelemetry {
        telemetryPublisher.value
    }

    private var pollTimer: Timer?
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private let queue = DispatchQueue(label: "com.notchkit.powercore.battery-monitor", qos: .utility)
    private var isMonitoring = false
    private let lock = NSLock()

    public init() {
        let initial = Self.fetchTelemetry()
        self.telemetryPublisher = CurrentValueSubject<BatteryTelemetry, Never>(initial)
    }

    // MARK: - Monitoring Control

    public func startMonitoring(interval: TimeInterval = 2.0) {
        lock.lock()
        defer { lock.unlock() }

        guard !isMonitoring else { return }
        isMonitoring = true

        // 1. Initial snapshot
        refresh()

        // 2. Periodic background poll
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.pollTimer?.invalidate()
            self.pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                self?.refresh()
            }
        }

        // 3. Register native IOKit power source run loop event notification
        registerPowerSourceNotification()
    }

    public func stopMonitoring() {
        lock.lock()
        defer { lock.unlock() }

        guard isMonitoring else { return }
        isMonitoring = false

        DispatchQueue.main.async { [weak self] in
            self?.pollTimer?.invalidate()
            self?.pollTimer = nil
        }

        if let source = powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            powerSourceRunLoopSource = nil
        }
    }

    public func refresh() {
        queue.async { [weak self] in
            guard let self = self else { return }
            let snapshot = Self.fetchTelemetry()
            DispatchQueue.main.async {
                self.telemetryPublisher.send(snapshot)
            }
        }
    }

    // MARK: - Hardware Telemetry Reading

    public static func fetchTelemetry() -> BatteryTelemetry {
        var percentage = 100
        var maxCapacity = 100
        var isCharging = false
        var isPluggedIn = false
        var isFullyCharged = false
        var amperage = 0
        var voltage = 12000
        var cycleCount = 0
        var designCapacity = 5000
        var fullChargeCapacity = 5000
        var timeRemainingMinutes: Int? = nil
        var adapterWatts: Int? = nil
        var adapterName: String? = nil
        var temperature: Double = 28.0

        // 1. Query AppleSmartBattery IORegistryEntry
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
               let dict = props?.takeRetainedValue() as? [String: Any] {

                if let cur = dict["CurrentCapacity"] as? Int {
                    percentage = cur
                }
                if let max = dict["MaxCapacity"] as? Int, max > 0 {
                    maxCapacity = max
                }
                if let charging = dict["IsCharging"] as? Bool {
                    isCharging = charging
                } else if let chargingInt = dict["IsCharging"] as? Int {
                    isCharging = (chargingInt != 0)
                }
                if let ext = dict["ExternalConnected"] as? Bool {
                    isPluggedIn = ext
                } else if let extInt = dict["ExternalConnected"] as? Int {
                    isPluggedIn = (extInt != 0)
                }
                if let fully = dict["FullyCharged"] as? Bool {
                    isFullyCharged = fully
                } else if let fullyInt = dict["FullyCharged"] as? Int {
                    isFullyCharged = (fullyInt != 0)
                }

                if let amp = dict["InstantAmperage"] as? Int {
                    amperage = amp
                } else if let amp = dict["Amperage"] as? Int {
                    amperage = amp
                }

                if let volt = dict["Voltage"] as? Int {
                    voltage = volt
                }
                if let cycles = dict["CycleCount"] as? Int {
                    cycleCount = cycles
                }

                if let batteryData = dict["BatteryData"] as? [String: Any] {
                    if let fcap = batteryData["FullChargeCapacity"] as? Int, fcap > 0 {
                        fullChargeCapacity = fcap
                    }
                    if let dcap = batteryData["DesignCapacity"] as? Int, dcap > 0 {
                        designCapacity = dcap
                    }
                }

                if let temp = dict["Temperature"] as? Int {
                    temperature = Double(temp) / 100.0
                }

                if let timeToFull = dict["AvgTimeToFull"] as? Int, timeToFull > 0, timeToFull < 65535 {
                    timeRemainingMinutes = timeToFull
                } else if let timeToEmpty = dict["AvgTimeToEmpty"] as? Int, timeToEmpty > 0, timeToEmpty < 65535 {
                    timeRemainingMinutes = timeToEmpty
                }

                if let adapterDetails = dict["AdapterDetails"] as? [String: Any] {
                    if let watts = adapterDetails["Watts"] as? Int {
                        adapterWatts = watts
                    }
                    if let desc = adapterDetails["Description"] as? String {
                        adapterName = desc
                    }
                }
            }
            IOObjectRelease(service)
        }

        // 2. Query IOPowerSources as supplemental verification
        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] {
            for ps in sources {
                if let desc = IOPSGetPowerSourceDescription(snapshot, ps)?.takeUnretainedValue() as? [String: Any] {
                    if let cur = desc[kIOPSCurrentCapacityKey] as? Int {
                        percentage = cur
                    }
                    if let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 {
                        maxCapacity = max
                    }
                    if let psIsCharging = desc[kIOPSIsChargingKey] as? Bool {
                        isCharging = psIsCharging
                    }
                    if let psPowerSource = desc[kIOPSPowerSourceStateKey] as? String {
                        if psPowerSource == kIOPSACPowerValue {
                            isPluggedIn = true
                        }
                    }
                    if let time = desc[kIOPSTimeToEmptyKey] as? Int, time > 0, timeRemainingMinutes == nil {
                        timeRemainingMinutes = time
                    }
                }
            }
        }

        // Calculate power wattage: P = (V * |A|) / 1,000,000 Watts
        var wattage = (Double(voltage) * Double(abs(amperage))) / 1_000_000.0
        if wattage < 0.05 && isPluggedIn {
            wattage = 0.0 // Battery idle in bypass mode
        }

        // Calculate health percentage
        let healthPercentage: Double
        if designCapacity > 0 && fullChargeCapacity > 0 {
            healthPercentage = min(100.0, max(0.0, (Double(fullChargeCapacity) / Double(designCapacity)) * 100.0))
        } else {
            healthPercentage = 100.0
        }

        // Determine bypass state
        let isBypassed = isPluggedIn && !isCharging && (percentage >= 50)
        let chargingState: ChargingState
        if isBypassed {
            chargingState = .bypassed
        } else if isCharging {
            chargingState = .charging
        } else if isFullyCharged && isPluggedIn {
            chargingState = .full
        } else {
            chargingState = .discharging
        }

        let powerSource = isPluggedIn ? "Power Adapter" : "Battery"

        return BatteryTelemetry(
            percentage: percentage,
            maxCapacity: maxCapacity,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            isFullyCharged: isFullyCharged,
            amperage: amperage,
            voltage: voltage,
            wattage: (wattage * 10).rounded() / 10.0,
            cycleCount: cycleCount,
            designCapacity: designCapacity,
            fullChargeCapacity: fullChargeCapacity,
            healthPercentage: (healthPercentage * 10).rounded() / 10.0,
            temperature: (temperature * 10).rounded() / 10.0,
            timeRemainingMinutes: timeRemainingMinutes,
            powerSource: powerSource,
            adapterWatts: adapterWatts,
            adapterName: adapterName,
            chargingState: chargingState,
            isBypassed: isBypassed,
            timestamp: Date()
        )
    }

    // MARK: - Native IOKit Power Notification

    private func registerPowerSourceNotification() {
        let callback: IOPowerSourceCallbackType = { _ in
            BatteryMonitor.shared.refresh()
        }

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            self.powerSourceRunLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }
}
