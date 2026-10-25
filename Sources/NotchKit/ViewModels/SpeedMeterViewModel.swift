import Foundation
import Combine
import SwiftUI
import NetCore
import ClipCore
import GRDB

@MainActor
public final class SpeedMeterViewModel: ObservableObject {
    public static let shared = SpeedMeterViewModel()

    @Published public var currentSpeed: NetworkSpeed = NetworkSpeed()
    @Published public var monthUsage: BandwidthUsage
    @Published public var todayUsage: BandwidthUsage
    @Published public var sessionUsage: BandwidthUsage
    @Published public var interfaceInfo: NetworkInterfaceInfo = NetworkInterfaceInfo()
    @Published public var isSpeedMeterEnabled: Bool = true
    @Published public var showingSettings: Bool = false

    private let monitor: NetworkSpeedMonitor
    private let dbManager: DatabaseManager
    private var cancellables = Set<AnyCancellable>()
    private var settingsCancellable: AnyDatabaseCancellable?

    public init(
        monitor: NetworkSpeedMonitor = .shared,
        databaseManager: DatabaseManager = .shared
    ) {
        self.monitor = monitor
        self.dbManager = databaseManager
        self.monthUsage = monitor.monthUsage
        self.todayUsage = monitor.todayUsage
        self.sessionUsage = monitor.sessionUsage
        self.interfaceInfo = monitor.interfaceInfo

        // Forward monitor published updates
        monitor.$currentSpeed
            .receive(on: RunLoop.main)
            .assign(to: &$currentSpeed)

        monitor.$monthUsage
            .receive(on: RunLoop.main)
            .assign(to: &$monthUsage)

        monitor.$todayUsage
            .receive(on: RunLoop.main)
            .assign(to: &$todayUsage)

        monitor.$sessionUsage
            .receive(on: RunLoop.main)
            .assign(to: &$sessionUsage)

        monitor.$interfaceInfo
            .receive(on: RunLoop.main)
            .assign(to: &$interfaceInfo)

        setupSettingsObservation()
    }

    private func setupSettingsObservation() {
        settingsCancellable = dbManager.makeSettingsObservation().start(
            in: dbManager.dbWriter,
            onError: { error in
                print("SpeedMeter settings observation error: \(error)")
            },
            onChange: { [weak self] newSettings in
                Task { @MainActor [weak self] in
                    self?.isSpeedMeterEnabled = newSettings.isSpeedMeterEnabled
                }
            }
        )
    }

    public var menuBarLabel: String {
        currentSpeed.menuBarLabel
    }

    public func resetMonthUsage() {
        monitor.resetCurrentMonthUsage()
        monthUsage = monitor.monthUsage
    }

    public func resetAllUsage() {
        monitor.resetAllStatistics()
        monthUsage = monitor.monthUsage
        todayUsage = monitor.todayUsage
        sessionUsage = monitor.sessionUsage
    }

    public func toggleSpeedMeterEnabled() {
        var current = (try? dbManager.dbWriter.read { try AppSettings.fetchOne($0, key: 1) }) ?? .default
        current.isSpeedMeterEnabled.toggle()
        try? dbManager.dbWriter.write { db in
            try current.update(db)
        }
        isSpeedMeterEnabled = current.isSpeedMeterEnabled
    }
}
