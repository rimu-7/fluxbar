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
        startSamplingTimer()
    }

    deinit {
        stopMonitoring()
    }

    private func setupScreenSleepObservers() {
        let sleepObs = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.timer?.cancel()
            self?.timer = nil
        }

        let wakeObs = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.startSamplingTimer()
        }

        sleepObservers = [sleepObs, wakeObs]
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

    public func startSamplingTimer(interval: TimeInterval = 1.0) {
        timer?.cancel()
        timer = nil

        let newTimer = DispatchSource.makeTimerSource(queue: samplerQueue)
        // 250ms leeway enables macOS timer coalescing on Apple Silicon Efficiency cores
        newTimer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(250))

        newTimer.setEventHandler { [weak self] in
            self?.sampleNetworkSpeed()
        }

        newTimer.resume()
        self.timer = newTimer
    }

    public func stopMonitoring() {
        timer?.cancel()
        timer = nil
        pathMonitor.cancel()
    }

    private func sampleNetworkSpeed() {
        lock.lock()
        let target = activeInterfaceName
        lock.unlock()

        let now = Date()
        let currentBytes = sampler.queryBytes(forInterface: target)

        guard let prevBytes = lastSampleBytes, let prevDate = lastSampleDate else {
            lastSampleBytes = currentBytes
            lastSampleDate = now
            return
        }

        let timeDelta = max(0.2, now.timeIntervalSince(prevDate))
        let deltaIn = NetworkByteSampler.computeDelta(current: currentBytes.bytesIn, previous: prevBytes.bytesIn)
        let deltaOut = NetworkByteSampler.computeDelta(current: currentBytes.bytesOut, previous: prevBytes.bytesOut)

        lastSampleBytes = currentBytes
        lastSampleDate = now

        let speedIn = UInt64(Double(deltaIn) / timeDelta)
        let speedOut = UInt64(Double(deltaOut) / timeDelta)
        let newSpeed = NetworkSpeed(bytesInPerSec: speedIn, bytesOutPerSec: speedOut, timestamp: now)

        // Record transfer in persistent store
        bandwidthStore.recordTransfer(bytesIn: deltaIn, bytesOut: deltaOut, date: now)

        let newMonth = bandwidthStore.getCurrentMonthUsage()
        let newToday = bandwidthStore.getTodayUsage()
        let newSession = bandwidthStore.getSessionUsage()

        DispatchQueue.main.async {
            self.currentSpeed = newSpeed
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
