import Foundation
import XCTest
@testable import ClipCore
import GRDB

@objcMembers
final class DatabasePerformanceTests: XCTestCase {
    var dbManager: DatabaseManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Use an isolated in-memory database for speed and deterministic testing
        dbManager = try DatabaseManager(inMemory: true)
    }

    override func tearDownWithError() throws {
        dbManager = nil
        try super.tearDownWithError()
    }

    // MARK: - Test 1: Atomic Upsert Deduplication

    func testAtomicUpsertDeduplication() throws {
        let content = "Hello World! This is a test clipboard content."
        let sourceApp = "Safari"

        // First copy
        let firstItem = try dbManager.recordClip(
            content: content,
            sourceAppBundleId: "com.apple.Safari",
            sourceAppName: sourceApp
        )
        XCTAssertNotNil(firstItem.id)
        XCTAssertEqual(firstItem.copyCount, 1)
        XCTAssertEqual(firstItem.content, content)

        // Wait a slight fraction to ensure distinct timestamp
        Thread.sleep(forTimeInterval: 0.05)

        // Second duplicate copy of identical content
        let secondItem = try dbManager.recordClip(
            content: content,
            sourceAppBundleId: "com.apple.Safari",
            sourceAppName: sourceApp
        )

        // Verifications:
        // 1. Same primary key ID
        XCTAssertEqual(secondItem.id, firstItem.id, "Upsert should maintain identical primary key ID")
        // 2. copyCount bumped to 2
        XCTAssertEqual(secondItem.copyCount, 2, "copyCount should increment on duplicate copy")
        // 3. updatedAt updated to newer timestamp
        XCTAssertGreaterThanOrEqual(secondItem.updatedAt, firstItem.updatedAt)

        // 4. Exact total row count in database must remain 1 (Zero duplicate rows)
        let allClips = try dbManager.queryClips(searchQuery: "", limit: 100)
        XCTAssertEqual(allClips.count, 1, "There must only be 1 row in clip_items after duplicate copies")
    }

    // MARK: - Test 2: Native SQLite Prune Trigger

    func testPruningTriggerPreservesPinnedAndEnforcesMaxHistory() throws {
        // Set maxHistory to 3 in app_settings
        var settings = try dbManager.fetchSettings()
        settings.maxHistory = 3
        try dbManager.updateSettings(settings)

        // Insert Item 1 (Unpinned)
        let item1 = try dbManager.recordClip(content: "Clip 1 (unpinned)")
        Thread.sleep(forTimeInterval: 0.02)

        // Insert Item 2 (Pinned)
        let item2 = try dbManager.recordClip(content: "Clip 2 (pinned)")
        try dbManager.togglePin(id: item2.id!)
        Thread.sleep(forTimeInterval: 0.02)

        // Insert Item 3 (Unpinned)
        _ = try dbManager.recordClip(content: "Clip 3 (unpinned)")
        Thread.sleep(forTimeInterval: 0.02)

        // Insert Item 4 (Unpinned) -> Now we have 3 unpinned items (1, 3, 4) + 1 pinned (2)
        _ = try dbManager.recordClip(content: "Clip 4 (unpinned)")
        Thread.sleep(forTimeInterval: 0.02)

        // At this point: exactly 3 unpinned items exist (maxHistory = 3). Total = 4.
        var clips = try dbManager.queryClips(searchQuery: "", limit: 100)
        XCTAssertEqual(clips.count, 4)

        // Now insert Item 5 (Unpinned) -> Trigger should prune the oldest unpinned item (Clip 1)
        _ = try dbManager.recordClip(content: "Clip 5 (unpinned)")

        clips = try dbManager.queryClips(searchQuery: "", limit: 100)

        // Verifications:
        // 1. Total clips should be 4 (3 unpinned + 1 pinned)
        XCTAssertEqual(clips.count, 4, "Total clips should equal maxHistory (3) + 1 pinned item")

        // 2. The oldest unpinned item (Clip 1) must be deleted
        let clipIds = clips.compactMap(\.id)
        XCTAssertFalse(clipIds.contains(item1.id!), "Oldest unpinned clip should have been pruned by SQLite trigger")

        // 3. Pinned item (Clip 2) MUST be preserved even though it is older
        XCTAssertTrue(clipIds.contains(item2.id!), "Pinned clip must NOT be pruned by SQLite trigger")
    }

    // MARK: - Test 3: SQLite FTS5 Full-Text Search

    func testFTS5FullTextSearch() throws {
        try dbManager.recordClip(content: "The quick brown fox jumps over the lazy dog", sourceAppName: "Safari")
        try dbManager.recordClip(content: "Swift Package Manager and zero N+1 database architecture", sourceAppName: "Xcode")
        try dbManager.recordClip(content: "SQLite FTS5 virtual table with sub-millisecond query execution", sourceAppName: "Terminal")

        // Match keyword 'fox'
        let foxMatches = try dbManager.queryClips(searchQuery: "fox")
        XCTAssertEqual(foxMatches.count, 1)
        XCTAssertTrue(foxMatches.first?.content.contains("fox") == true)

        // Match keyword 'architecture'
        let archMatches = try dbManager.queryClips(searchQuery: "architecture")
        XCTAssertEqual(archMatches.count, 1)
        XCTAssertTrue(archMatches.first?.content.contains("architecture") == true)

        // Match sourceAppName 'Terminal'
        let termMatches = try dbManager.queryClips(searchQuery: "Terminal")
        XCTAssertEqual(termMatches.count, 1)
        XCTAssertEqual(termMatches.first?.sourceAppName, "Terminal")

        // Match prefix token 'execut' -> should match 'execution'
        let prefixMatches = try dbManager.queryClips(searchQuery: "execut")
        XCTAssertEqual(prefixMatches.count, 1)

        // Match non-existent word
        let noMatches = try dbManager.queryClips(searchQuery: "nonexistentkeywordxyz")
        XCTAssertEqual(noMatches.count, 0)
    }

    // MARK: - Test 4: Delete Clip & Clear Unpinned

    func testDeleteAndClearUnpinned() throws {
        let clip1 = try dbManager.recordClip(content: "To be pinned")
        try dbManager.togglePin(id: clip1.id!)

        _ = try dbManager.recordClip(content: "To be cleared")
        let clip3 = try dbManager.recordClip(content: "To be deleted")

        // Delete clip 3
        try dbManager.deleteClip(id: clip3.id!)
        var remaining = try dbManager.queryClips(searchQuery: "", limit: 100)
        XCTAssertEqual(remaining.count, 2)
        XCTAssertFalse(remaining.contains(where: { $0.id == clip3.id }))

        // Clear unpinned -> only pinned clip 1 should remain
        try dbManager.clearUnpinned()
        remaining = try dbManager.queryClips(searchQuery: "", limit: 100)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, clip1.id)
    }
}
