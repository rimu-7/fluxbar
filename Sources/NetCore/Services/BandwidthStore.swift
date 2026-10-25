import Foundation
import AppKit
import GRDB

/// Thread-safe SQLite store for persisting monthly and daily network bandwidth usage statistics.
public final class BandwidthStore: @unchecked Sendable {
    public static let shared = BandwidthStore()

    private let dbQueue: DatabaseQueue
    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter
    private let monthFormatter: DateFormatter
    private let lock = NSLock()

    // In-memory cache for fast, lock-free UI reads
    private var cachedMonthUsage: BandwidthUsage
    private var cachedTodayUsage: BandwidthUsage
    private var cachedSessionUsage: BandwidthUsage

    // Low-energy batch write buffer (flushes every 5 minutes or on sleep/quit)
    private var pendingBytesIn: UInt64 = 0
    private var pendingBytesOut: UInt64 = 0
    private var lastFlushDate: Date = Date()
    private var lifecycleObservers: [NSObjectProtocol] = []

    public init(databasePath: String? = nil) {
        let path: String
        if let customPath = databasePath {
            path = customPath
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let legacyDir = appSupport.appendingPathComponent("NotchKit", isDirectory: true)
            let fluxDir = appSupport.appendingPathComponent("FluxBar", isDirectory: true)
            let dir = FileManager.default.fileExists(atPath: legacyDir.appendingPathComponent("bandwidth.sqlite").path) ? legacyDir : fluxDir
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            path = dir.appendingPathComponent("bandwidth.sqlite").path
        }

        var config = Configuration()
        config.qos = .utility
        config.label = "FluxBar.BandwidthStore"
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL;")
            try db.execute(sql: "PRAGMA synchronous = NORMAL;")
            try db.execute(sql: "PRAGMA cache_size = -1024;")
        }

        // Initialize SQLite queue with WAL mode
        do {
            dbQueue = try DatabaseQueue(path: path, configuration: config)
            try dbQueue.write { db in
                try db.execute(sql: """
                    CREATE TABLE IF NOT EXISTS bandwidth_records (
                        period_type TEXT NOT NULL,
                        period_key TEXT NOT NULL,
                        bytes_in INTEGER NOT NULL DEFAULT 0,
                        bytes_out INTEGER NOT NULL DEFAULT 0,
                        updated_at REAL NOT NULL,
                        PRIMARY KEY (period_type, period_key)
                    );
                """)
            }
        } catch {
            fatalError("Failed to initialize BandwidthStore database at \(path): \(error)")
        }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone.current
        self.dateFormatter = df

        let mf = DateFormatter()
        mf.dateFormat = "yyyy-MM"
        mf.timeZone = TimeZone.current
        self.monthFormatter = mf

        let now = Date()
        let monthKey = mf.string(from: now)
        let dayKey = df.string(from: now)

        self.cachedMonthUsage = BandwidthUsage(periodType: "month", periodKey: monthKey)
        self.cachedTodayUsage = BandwidthUsage(periodType: "day", periodKey: dayKey)
        self.cachedSessionUsage = BandwidthUsage(periodType: "session", periodKey: "session")

        // Load initial values from DB
        reloadInitialStats(now: now)
        setupLifecycleObservers()
    }

    deinit {
        flushToDisk()
    }

    private func setupLifecycleObservers() {
        let termObs = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.flushToDisk()
        }

        let sleepObs = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.flushToDisk()
        }

        lifecycleObservers = [termObs, sleepObs]
    }

    private func reloadInitialStats(now: Date) {
        let monthKey = monthFormatter.string(from: now)
        let dayKey = dateFormatter.string(from: now)

        try? dbQueue.read { db in
            if let row = try Row.fetchOne(db, sql: "SELECT bytes_in, bytes_out, updated_at FROM bandwidth_records WHERE period_type = 'month' AND period_key = ?", arguments: [monthKey]) {
                let bi: Int64 = row["bytes_in"]
                let bo: Int64 = row["bytes_out"]
                let ts: Double = row["updated_at"]
                self.cachedMonthUsage = BandwidthUsage(
                    periodType: "month",
                    periodKey: monthKey,
                    bytesIn: UInt64(max(0, bi)),
                    bytesOut: UInt64(max(0, bo)),
                    updatedAt: Date(timeIntervalSince1970: ts)
                )
            }

            if let row = try Row.fetchOne(db, sql: "SELECT bytes_in, bytes_out, updated_at FROM bandwidth_records WHERE period_type = 'day' AND period_key = ?", arguments: [dayKey]) {
                let bi: Int64 = row["bytes_in"]
                let bo: Int64 = row["bytes_out"]
                let ts: Double = row["updated_at"]
                self.cachedTodayUsage = BandwidthUsage(
                    periodType: "day",
                    periodKey: dayKey,
                    bytesIn: UInt64(max(0, bi)),
                    bytesOut: UInt64(max(0, bo)),
                    updatedAt: Date(timeIntervalSince1970: ts)
                )
            }
        }
    }

    /// Records transferred bytes into monthly, daily, and session totals.
    /// Accumulates in RAM and flushes to SQLite every 5 minutes to prevent waking disk I/O.
    public func recordTransfer(bytesIn: UInt64, bytesOut: UInt64, date: Date = Date()) {
        guard bytesIn > 0 || bytesOut > 0 else { return }

        let monthKey = monthFormatter.string(from: date)
        let dayKey = dateFormatter.string(from: date)

        lock.lock()
        // Update in-memory session usage
        cachedSessionUsage.bytesIn += bytesIn
        cachedSessionUsage.bytesOut += bytesOut
        cachedSessionUsage.updatedAt = date

        // Check for month rollover
        if cachedMonthUsage.periodKey != monthKey {
            cachedMonthUsage = BandwidthUsage(periodType: "month", periodKey: monthKey)
        }
        cachedMonthUsage.bytesIn += bytesIn
        cachedMonthUsage.bytesOut += bytesOut
        cachedMonthUsage.updatedAt = date

        // Check for day rollover
        if cachedTodayUsage.periodKey != dayKey {
            cachedTodayUsage = BandwidthUsage(periodType: "day", periodKey: dayKey)
        }
        cachedTodayUsage.bytesIn += bytesIn
        cachedTodayUsage.bytesOut += bytesOut
        cachedTodayUsage.updatedAt = date

        // Accumulate pending batch for disk write
        pendingBytesIn += bytesIn
        pendingBytesOut += bytesOut
        let shouldFlush = date.timeIntervalSince(lastFlushDate) >= 300 // 5 minutes
        lock.unlock()

        if shouldFlush {
            flushToDisk()
        }
    }

    /// Flushes accumulated byte counters into SQLite database in a single batch
    public func flushToDisk() {
        lock.lock()
        guard pendingBytesIn > 0 || pendingBytesOut > 0 else {
            lock.unlock()
            return
        }
        let toFlushIn = pendingBytesIn
        let toFlushOut = pendingBytesOut
        pendingBytesIn = 0
        pendingBytesOut = 0
        let date = Date()
        lastFlushDate = date
        let monthKey = monthFormatter.string(from: date)
        let dayKey = dateFormatter.string(from: date)
        lock.unlock()

        let inInt = Int64(min(toFlushIn, UInt64(Int64.max)))
        let outInt = Int64(min(toFlushOut, UInt64(Int64.max)))
        let ts = date.timeIntervalSince1970

        try? dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO bandwidth_records (period_type, period_key, bytes_in, bytes_out, updated_at)
                VALUES ('month', ?, ?, ?, ?)
                ON CONFLICT(period_type, period_key) DO UPDATE SET
                    bytes_in = bytes_in + excluded.bytes_in,
                    bytes_out = bytes_out + excluded.bytes_out,
                    updated_at = excluded.updated_at;

                INSERT INTO bandwidth_records (period_type, period_key, bytes_in, bytes_out, updated_at)
                VALUES ('day', ?, ?, ?, ?)
                ON CONFLICT(period_type, period_key) DO UPDATE SET
                    bytes_in = bytes_in + excluded.bytes_in,
                    bytes_out = bytes_out + excluded.bytes_out,
                    updated_at = excluded.updated_at;
                """,
                arguments: [monthKey, inInt, outInt, ts, dayKey, inInt, outInt, ts]
            )
        }
    }

    public func getCurrentMonthUsage() -> BandwidthUsage {
        lock.lock()
        defer { lock.unlock() }
        return cachedMonthUsage
    }

    public func getTodayUsage() -> BandwidthUsage {
        lock.lock()
        defer { lock.unlock() }
        return cachedTodayUsage
    }

    public func getSessionUsage() -> BandwidthUsage {
        lock.lock()
        defer { lock.unlock() }
        return cachedSessionUsage
    }

    /// Resets the bandwidth counters for the current month.
    public func resetCurrentMonthUsage() {
        let monthKey = monthFormatter.string(from: Date())
        lock.lock()
        cachedMonthUsage = BandwidthUsage(periodType: "month", periodKey: monthKey, bytesIn: 0, bytesOut: 0, updatedAt: Date())
        lock.unlock()

        try? dbQueue.write { db in
            try db.execute(
                sql: "UPDATE bandwidth_records SET bytes_in = 0, bytes_out = 0, updated_at = ? WHERE period_type = 'month' AND period_key = ?",
                arguments: [Date().timeIntervalSince1970, monthKey]
            )
        }
    }

    /// Resets all historical bandwidth statistics.
    public func resetAllStatistics() {
        let now = Date()
        let monthKey = monthFormatter.string(from: now)
        let dayKey = dateFormatter.string(from: now)

        lock.lock()
        cachedMonthUsage = BandwidthUsage(periodType: "month", periodKey: monthKey)
        cachedTodayUsage = BandwidthUsage(periodType: "day", periodKey: dayKey)
        cachedSessionUsage = BandwidthUsage(periodType: "session", periodKey: "session")
        lock.unlock()

        try? dbQueue.write { db in
            try db.execute(sql: "DELETE FROM bandwidth_records;")
        }
    }
}
