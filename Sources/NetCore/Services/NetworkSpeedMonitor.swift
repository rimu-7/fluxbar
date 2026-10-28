import Foundation
import AppKit
import Network
import Combine

/// Real-time network speed monitor and bandwidth usage coordinator.
public final class NetworkSpeedMonitor: ObservableObject, @unchecked Sendable {
    public static let shared = NetworkSpeedMonitor()

    @Published public private(set) var currentSpeed: NetworkSpeed = NetworkSpeed()
    @Published public private(set) var monthUsage: BandwidthUsage
    @Published public private(set) var todayUsage: BandwidthUsage
    @Published public private(set) var sessionUsage: BandwidthUsage
    @Published public private(set) var interfaceInfo: NetworkInterfaceInfo = NetworkInterfaceInfo()

    private let pathMonitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(label: "com.notchkit.NetCore.pathMonitor", qos: .utility)
    // Scheduled on .utility to guarantee execution on Apple Silicon Efficiency (E) cores
    private let samplerQueue = DispatchQueue(label: "com.notchkit.NetCore.sampler", qos: .utility)

    private let sampler = NetworkByteSampler()
    private let bandwidthStore: BandwidthStore
    private var timer: DispatchSourceTimer?
    private var sleepObservers: [NSObjectProtocol] = []

    private var lastSampleBytes: (bytesIn: UInt64, bytesOut: UInt64)?
    private var lastSampleDate: Date?
    private var activeInterfaceName: String? = "en0"

    private let lock = NSLock()

    public init(bandwidthStore: BandwidthStore = .shared) {
        self.bandwidthStore = bandwidthStore
        self.monthUsage = bandwidthStore.getCurrentMonthUsage()
        self.todayUsage = bandwidthStore.getTodayUsage()
        self.sessionUsage = bandwidthStore.getSessionUsage()
        self.pathMonitor = NWPathMonitor()

        setupPathMonitoring()
        setupScreenSleepObservers()
        applySamplingInterval()
    }

    deinit {
        stopMonitoring()
    }

    private func setupScreenSleepObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let pause: (Notification) -> Void = { [weak self] _ in self?.pauseSampling() }
        let resume: (Notification) -> Void = { [weak self] _ in self?.applySamplingInterval() }
        sleepObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil, using: pause),
            center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: nil, using: pause),
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil, using: resume),
            center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: nil, using: resume),
            NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: nil, using: resume)
        ]
    }

    // MARK: - Adaptive sampling

    /// Menu bar meter shown: sample every second so the numbers feel live.
    private var isMeterVisible = true
    /// Speed tab open: also publish usage totals.
    private var isDetailVisible = false
    private var currentInterval: TimeInterval = 0

    /// Call when the menu bar speed meter is shown or hidden.
    public func setMeterVisible(_ visible: Bool) {
        lock.lock(); isMeterVisible = visible; lock.unlock()
        applySamplingInterval()
    }

    /// Call when the Speed tab opens or closes.
    public func setDetailVisible(_ visible: Bool) {
        lock.lock(); isDetailVisible = visible; lock.unlock()
        if visible { publishUsage() }
        applySamplingInterval()
    }

    /// 1 s when someone is looking, 2 s in Low Power Mode, 30 s in the background (usage totals only).
    private func applySamplingInterval() {
        lock.lock()
        let live = isMeterVisible || isDetailVisible
        lock.unlock()
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let interval: TimeInterval = live ? (lowPower ? 2.0 : 1.0) : 30.0
        samplerQueue.async { [weak self] in
            guard let self else { return }
            if self.timer != nil && self.currentInterval == interval { return }
            self.startSamplingTimer(interval: interval)
        }
    }

    private func pauseSampling() {
        samplerQueue.async { [weak self] in
            guard let self else { return }
            self.timer?.cancel()
            self.timer = nil
            self.currentInterval = 0
            // Baseline is kept: the first sample after wake counts bytes moved meanwhile (e.g. a
            // download running with the screen off), averaged over the gap so there is no speed spike.
            self.bandwidthStore.flushToDisk()
        }
    }

    private func setupPathMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }

            let isConnected = (path.status == .satisfied)
            var activeName = "en0"
            var typeName = "Wi-Fi"

            if let firstInterface = path.availableInterfaces.first {
                activeName = firstInterface.name
                switch firstInterface.type {
                case .wifi:
                    typeName = "Wi-Fi"
                case .wiredEthernet:
                    typeName = "Ethernet"
                case .cellular:
                    typeName = "Cellular"
                default:
                    typeName = "Network"
                }
            }

            self.lock.lock()
            self.activeInterfaceName = activeName
            self.lock.unlock()

            let newInfo = NetworkInterfaceInfo(name: activeName, isConnected: isConnected, typeName: typeName)
            DispatchQueue.main.async {
                self.interfaceInfo = newInfo
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    /// Must run on `samplerQueue`.
    private func startSamplingTimer(interval: TimeInterval = 1.0) {
        timer?.cancel()
        currentInterval = interval

        let newTimer = DispatchSource.makeTimerSource(queue: samplerQueue)
        // 25% leeway lets macOS coalesce this wake-up with others.
        newTimer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(Int(interval * 250)))
        newTimer.setEventHandler { [weak self] in
            self?.sampleNetworkSpeed()
        }
        newTimer.resume()
        self.timer = newTimer
    }

    public func stopMonitoring() {
        samplerQueue.sync {
            timer?.cancel()
            timer = nil
        }
        pathMonitor.cancel()
    }

    private var sampledInterfaceName: String?

    /// Runs on `samplerQueue`.
    private func sampleNetworkSpeed() {
        lock.lock()
        let target = activeInterfaceName
        let detail = isDetailVisible
        lock.unlock()

        let now = Date()
        let currentBytes = sampler.queryBytes(forInterface: target)

        // New interface (Wi-Fi <-> Ethernet, VPN): its counters are unrelated to the old ones, start over.
        guard target == sampledInterfaceName, let prevBytes = lastSampleBytes, let prevDate = lastSampleDate else {
            sampledInterfaceName = target
            lastSampleBytes = currentBytes
            lastSampleDate = now
            return
        }

        let timeDelta = max(0.2, now.timeIntervalSince(prevDate))
        let deltaIn = NetworkByteSampler.computeDelta(current: currentBytes.bytesIn, previous: prevBytes.bytesIn)
        let deltaOut = NetworkByteSampler.computeDelta(current: currentBytes.bytesOut, previous: prevBytes.bytesOut)

        lastSampleBytes = currentBytes
        lastSampleDate = now

        let newSpeed = NetworkSpeed(
            bytesInPerSec: UInt64(Double(deltaIn) / timeDelta),
            bytesOutPerSec: UInt64(Double(deltaOut) / timeDelta),
            timestamp: now
        )
        bandwidthStore.recordTransfer(bytesIn: deltaIn, bytesOut: deltaOut, date: now)

        DispatchQueue.main.async {
            if self.currentSpeed.bytesInPerSec != newSpeed.bytesInPerSec || self.currentSpeed.bytesOutPerSec != newSpeed.bytesOutPerSec {
                self.currentSpeed = newSpeed
            }
        }
        if detail { publishUsage() }
    }

    private func publishUsage() {
        let newMonth = bandwidthStore.getCurrentMonthUsage()
        let newToday = bandwidthStore.getTodayUsage()
        let newSession = bandwidthStore.getSessionUsage()
        DispatchQueue.main.async {
            self.monthUsage = newMonth
            self.todayUsage = newToday
            self.sessionUsage = newSession
        }
    }

    public func resetCurrentMonthUsage() {
        bandwidthStore.resetCurrentMonthUsage()
        let refreshed = bandwidthStore.getCurrentMonthUsage()
        DispatchQueue.main.async {
            self.monthUsage = refreshed
        }
    }

    public func resetAllStatistics() {
        bandwidthStore.resetAllStatistics()
        let newMonth = bandwidthStore.getCurrentMonthUsage()
        let newToday = bandwidthStore.getTodayUsage()
        let newSession = bandwidthStore.getSessionUsage()
        DispatchQueue.main.async {
            self.monthUsage = newMonth
            self.todayUsage = newToday
            self.sessionUsage = newSession
        }
    }
}
