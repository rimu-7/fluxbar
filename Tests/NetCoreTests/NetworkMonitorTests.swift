import XCTest
import Foundation
@testable import NetCore

@objcMembers
final class NetworkMonitorTests: XCTestCase {

    func testNetworkSpeedFormatting() throws {
        XCTAssertEqual(NetworkSpeed.formatRate(0), "0 B/s")
        XCTAssertEqual(NetworkSpeed.formatRate(512), "512 B/s")
        XCTAssertEqual(NetworkSpeed.formatRate(1024), "1.00 KB/s")
        XCTAssertEqual(NetworkSpeed.formatRate(1048576), "1.00 MB/s")
        XCTAssertEqual(NetworkSpeed.formatRate(1073741824), "1.00 GB/s")

        let speed = NetworkSpeed(bytesInPerSec: 0, bytesOutPerSec: 1045) // ~1.02 KB/s
        XCTAssertEqual(speed.formattedDownload, "0 B/s")
        XCTAssertEqual(speed.formattedUpload, "1.02 KB/s")
        XCTAssertEqual(speed.menuBarLabel, "↓ 0 B/s  ↑ 1.02 KB/s")
    }

    func testByteSamplerDeltaAndRollover() throws {
        // Standard monotonic delta
        let delta1 = NetworkByteSampler.computeDelta(current: 5000, previous: 2000)
        XCTAssertEqual(delta1, 3000)

        // 32-bit hardware counter rollover
        let max32 = UInt64(UInt32.max)
        let delta2 = NetworkByteSampler.computeDelta(current: 100, previous: max32 - 100)
        XCTAssertEqual(delta2, 201)
    }

    func testBandwidthStoreMonthlyAndDailyTracking() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbPath = tempDir.appendingPathComponent("test_bandwidth.sqlite").path

        let store = BandwidthStore(databasePath: dbPath)

        // Record transfers
        store.recordTransfer(bytesIn: 1048576, bytesOut: 524288) // 1 MB down, 0.5 MB up
        store.recordTransfer(bytesIn: 1048576, bytesOut: 524288) // Another 1 MB down, 0.5 MB up

        let month = store.getCurrentMonthUsage()
        XCTAssertEqual(month.bytesIn, 2097152)
        XCTAssertEqual(month.bytesOut, 1048576)
        XCTAssertEqual(month.totalBytes, 3145728)
        XCTAssertEqual(month.formattedTotal, "3.00 MB")

        let today = store.getTodayUsage()
        XCTAssertEqual(today.bytesIn, 2097152)
        XCTAssertEqual(today.bytesOut, 1048576)

        let session = store.getSessionUsage()
        XCTAssertEqual(session.bytesIn, 2097152)
        XCTAssertEqual(session.bytesOut, 1048576)

        // Reset current month
        store.resetCurrentMonthUsage()
        let resetMonth = store.getCurrentMonthUsage()
        XCTAssertEqual(resetMonth.bytesIn, 0)
        XCTAssertEqual(resetMonth.bytesOut, 0)
        XCTAssertEqual(resetMonth.totalBytes, 0)

        // Clean up temp dir
        try? FileManager.default.removeItem(at: tempDir)
    }
}
