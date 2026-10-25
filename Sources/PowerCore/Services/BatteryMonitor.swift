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

    public private(set) var isPopoverVisible: Bool = false
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private let queue = DispatchQueue(label: "com.notchkit.powercore.battery-monitor", qos: .utility)
    private var isMonitoring = false
    private let lock = NSLock()

    public init() {
        let initial = Self.fetchTelemetry(deep: true)
        self.telemetryPublisher = CurrentValueSubject<BatteryTelemetry, Never>(initial)
    }

    // MARK: - Monitoring Control

    /// Starts event-driven monitoring using native IOKit power source notifications (Zero periodic polling timers)
    public func startMonitoring(interval: TimeInterval = 2.0) {
        lock.lock()
        defer { lock.unlock() }

        guard !isMonitoring else { return }
        isMonitoring = true

        // 1. Initial snapshot
        refresh(deep: false)

        // 2. Register native IOKit power source run loop event notification (0% idle CPU)
        registerPowerSourceNotification()
    }

    public func stopMonitoring() {
        lock.lock()
        defer { lock.unlock() }

        guard isMonitoring else { return }
        isMonitoring = false

        if let source = powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            powerSourceRunLoopSource = nil
        }
    }

    /// Sets whether the popover UI is open, pausing deep AppleSmartBattery/FedDetails polling when closed
    public func setPopoverVisible(_ visible: Bool) {
        lock.lock()
        self.isPopoverVisible = visible
        lock.unlock()

        if visible {
            refresh(deep: true)
        }
    }

    public func refresh(deep: Bool? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let shouldDeep = deep ?? self.isPopoverVisible
            let snapshot = Self.fetchTelemetry(deep: shouldDeep)
            DispatchQueue.main.async {
                self.telemetryPublisher.send(snapshot)
            }
        }
    }

    // MARK: - Hardware Telemetry Reading

    public static func fetchTelemetry(deep: Bool = true) -> BatteryTelemetry {
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
        var adapterVoltage: Double? = nil
        var adapterAmperage: Double? = nil
        var inputPowerWatts: Double? = nil
        var inputVoltage: Double? = nil
        var inputCurrentAmps: Double? = nil
        var activeProfileIndex: Int? = nil
        var chargerPortIndex: Int? = nil
        var adapterProfiles: [String] = []
        var connectedAccessories: [ConnectedAccessoryPower] = []
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
                    if let v = adapterDetails["AdapterVoltage"] as? Int, v > 0 {
                        adapterVoltage = Double(v) / 1000.0
                    }
                    if let a = adapterDetails["Current"] as? Int, a > 0 {
                        adapterAmperage = Double(a) / 1000.0
                    }
                    if let hvcIdx = adapterDetails["UsbHvcHvcIndex"] as? Int {
                        activeProfileIndex = hvcIdx
                    }
                    if let menu = adapterDetails["UsbHvcMenu"] as? [[String: Any]] {
                        for item in menu {
                            if let mv = item["MaxVoltage"] as? Int, let ma = item["MaxCurrent"] as? Int {
                                let v = Double(mv) / 1000.0
                                let a = Double(ma) / 1000.0
                                let w = (v * a * 10).rounded() / 10.0
                                adapterProfiles.append("\(Int(v))V @ \(String(format: "%.1f", a))A (\(Int(w))W)")
                            }
                        }
                    }
                }

                if let pwrDist = dict["PowerDistribution"] as? [String: Any] {
                    if let ip = pwrDist["IPDInputPower"] as? Int, ip > 0 {
                        inputPowerWatts = (Double(ip) / 100.0).rounded() / 10.0
                    }
                    if let iv = pwrDist["IPDInputVoltage"] as? Int, iv > 0 {
                        inputVoltage = (Double(iv) / 100.0).rounded() / 10.0
                    }
                    if let ia = pwrDist["IPDInputCurrent"] as? Int, ia > 0 {
                        inputCurrentAmps = (Double(ia) / 100.0).rounded() / 10.0
                    }
                }

                if let fedList = dict["FedDetails"] as? [[String: Any]] {
                    for (idx, fed) in fedList.enumerated() {
                        let isConn = (fed["FedExternalConnected"] as? Int ?? 0) != 0 || (fed["FedExternalConnected"] as? Bool ?? false)
                        let role = fed["FedPortPowerRole"] as? Int ?? 0 // 0 = Sink (Mac receiving power), 1 = Source (Mac powering peripheral)
                        let vendor = fed["FedVendorID"] as? Int ?? 0

                        if isConn {
                            if role == 0 && (vendor == 10007 || vendor == 0) {
                                chargerPortIndex = idx + 1
                            } else if role == 1 || (vendor != 10007 && vendor != 0) {
                                let soc = fed["FedStateOfCharge"] as? Int
                                let validSoc = (soc != nil && soc! > 0 && soc! <= 100) ? soc : nil
                                let devName = (vendor == 10007 || vendor == 0x05AC) ? "Apple Device (iPhone / Watch)" : "USB-C Peripheral"
                                connectedAccessories.append(
                                    ConnectedAccessoryPower(
                                        portIndex: idx + 1,
                                        portName: "Thunderbolt / USB-C Port \(idx + 1)",
                                        deviceName: devName,
                                        isChargingFromMac: true,
                                        batteryLevel: validSoc,
                                        estimatedOutputWatts: 7.5
                                    )
                                )
                            }
                        }
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
            timestamp: Date(),
            adapterVoltage: adapterVoltage,
            adapterAmperage: adapterAmperage,
            inputPowerWatts: inputPowerWatts,
            inputVoltage: inputVoltage,
            inputCurrentAmps: inputCurrentAmps,
            activeProfileIndex: activeProfileIndex,
            chargerPortIndex: chargerPortIndex,
            adapterProfiles: adapterProfiles,
            connectedAccessories: connectedAccessories
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
