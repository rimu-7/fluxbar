import Foundation
import GRDB

public struct DatabaseStats: Sendable, Equatable {
    public let totalClips: Int
    public let pinnedClips: Int
    public let fileSizeBytes: Int64

    public init(totalClips: Int, pinnedClips: Int, fileSizeBytes: Int64) {
        self.totalClips = totalClips
        self.pinnedClips = pinnedClips
        self.fileSizeBytes = fileSizeBytes
    }

    public var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSizeBytes)
    }
}

public final class DatabaseManager: @unchecked Sendable {
    public static let shared: DatabaseManager = {
        do {
            return try DatabaseManager()
        } catch {
            fatalError("Failed to initialize DatabaseManager: \(error)")
        }
    }()

    public let dbWriter: any DatabaseWriter
    public let dbPath: String?

    public static var defaultDatabaseURL: URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directoryURL = appSupport.appendingPathComponent("ClipSuite", isDirectory: true)
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        return directoryURL.appendingPathComponent("clips.db")
    }

    public init(databaseURL: URL? = nil) throws {
        let url = databaseURL ?? Self.defaultDatabaseURL
        self.dbPath = url.path

        var config = Configuration()
        config.qos = .userInitiated
        config.foreignKeysEnabled = true
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL;")
            try db.execute(sql: "PRAGMA synchronous = NORMAL;")
            try db.execute(sql: "PRAGMA foreign_keys = ON;")
            try db.execute(sql: "PRAGMA recursive_triggers = ON;")
            try db.execute(sql: "PRAGMA wal_autocheckpoint = 25;")
            try db.execute(sql: "PRAGMA journal_size_limit = 65536;")
        }

        let pool = try DatabasePool(path: url.path, configuration: config)
        self.dbWriter = pool
        try Migrations.migrator.migrate(pool)
    }

    /// In-memory database initializer specifically for testing
    public init(inMemory: Bool) throws {
        self.dbPath = nil
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON;")
            try db.execute(sql: "PRAGMA recursive_triggers = ON;")
        }
        let queue = try DatabaseQueue(configuration: config)
        self.dbWriter = queue
        try Migrations.migrator.migrate(queue)
    }

    // MARK: - Single-Pass Atomic Upsert

    @discardableResult
    public func recordClip(
        content: String,
        sourceAppBundleId: String? = nil,
        sourceAppName: String? = nil,
        formatType: String = "text",
        rtfData: Data? = nil,
        htmlContent: String? = nil,
        fileURL: String? = nil
    ) throws -> ClipItem {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DatabaseError(message: "Cannot save empty clip")
        }

        let hash = ClipItem.computeHash(for: trimmed)
        let charCount = trimmed.count
        let lineCount = ClipItem.computeLineCount(for: trimmed)
        let now = Date()

        // Externalize large payloads exceeding 100 KB to keep SQLite under 5 MB
        var storedRtfData = rtfData
        if let rtf = rtfData, rtf.count > ClipBlobManager.blobThresholdBytes {
            let blobRef = ClipBlobManager.shared.storeBlob(data: rtf)
            storedRtfData = blobRef.data(using: .utf8)
        }

        return try dbWriter.write { db in
            let sql = """
            INSERT INTO clip_items (
                content, contentHash, charCount, lineCount,
                sourceAppBundleId, sourceAppName, copyCount, isPinned,
                formatType, rtfData, htmlContent, fileURL,
                createdAt, updatedAt
            ) VALUES (?, ?, ?, ?, ?, ?, 1, 0, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(contentHash) DO UPDATE SET
                content = excluded.content,
                charCount = excluded.charCount,
                lineCount = excluded.lineCount,
                updatedAt = excluded.updatedAt,
                copyCount = clip_items.copyCount + 1,
                sourceAppBundleId = coalesce(excluded.sourceAppBundleId, clip_items.sourceAppBundleId),
                sourceAppName = coalesce(excluded.sourceAppName, clip_items.sourceAppName),
                formatType = coalesce(excluded.formatType, clip_items.formatType),
                rtfData = coalesce(excluded.rtfData, clip_items.rtfData),
                htmlContent = coalesce(excluded.htmlContent, clip_items.htmlContent),
                fileURL = coalesce(excluded.fileURL, clip_items.fileURL)
            RETURNING *;
            """
            guard let item = try ClipItem.fetchOne(
                db,
                sql: sql,
                arguments: [trimmed, hash, charCount, lineCount, sourceAppBundleId, sourceAppName, formatType, storedRtfData, htmlContent, fileURL, now, now]
            ) else {
                throw DatabaseError(message: "Failed to fetch saved clip item")
            }
            return item
        }
    }

    // MARK: - Query Clips (Compound Index & FTS5)

    public func queryClips(
        searchQuery: String = "",
        limit: Int = 100,
        pinnedOnly: Bool = false
    ) throws -> [ClipItem] {
        try dbWriter.read { db in
            let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                // Single-statement query using compound index (isPinned DESC, updatedAt DESC)
                if pinnedOnly {
                    let sql = """
                    SELECT * FROM clip_items
                    WHERE isPinned = 1
                    ORDER BY updatedAt DESC
                    LIMIT ?;
                    """
                    return try ClipItem.fetchAll(db, sql: sql, arguments: [limit])
                } else {
                    let sql = """
                    SELECT * FROM clip_items
                    ORDER BY isPinned DESC, updatedAt DESC
                    LIMIT ?;
                    """
                    return try ClipItem.fetchAll(db, sql: sql, arguments: [limit])
                }
            } else {
                // SQLite FTS5 Virtual Table JOIN
                // Sanitize and format FTS5 query token
                let sanitized = Self.sanitizeFTS5Query(trimmed)
                let sql = """
                SELECT c.*
                FROM clip_items c
                JOIN clip_items_fts f ON c.id = f.rowid
                WHERE clip_items_fts MATCH ?
                  AND (? = 0 OR c.isPinned = 1)
                ORDER BY c.isPinned DESC, c.updatedAt DESC
                LIMIT ?;
                """
                return try ClipItem.fetchAll(db, sql: sql, arguments: [sanitized, pinnedOnly ? 1 : 0, limit])
            }
        }
    }

    public static func sanitizeFTS5Query(_ query: String) -> String {
        // Strip unsafe FTS5 control characters and construct token prefix matching
        let clean = query.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        if clean.isEmpty {
            return "\"\(query.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return clean.map { "\"\($0)\"*" }.joined(separator: " ")
    }

    // MARK: - Pin / Unpin

    @discardableResult
    public func togglePin(id: Int64) throws -> Bool {
        try dbWriter.write { db in
            let sql = """
            UPDATE clip_items
            SET isPinned = CASE WHEN isPinned = 1 THEN 0 ELSE 1 END,
                updatedAt = ?
            WHERE id = ?;
            """
            try db.execute(sql: sql, arguments: [Date(), id])
            return db.changesCount > 0
        }
    }

    // MARK: - Delete / Clear

    @discardableResult
    public func deleteClip(id: Int64) throws -> Bool {
        try dbWriter.write { db in
            try db.execute(sql: "DELETE FROM clip_items WHERE id = ?;", arguments: [id])
            return db.changesCount > 0
        }
    }

    public func clearUnpinned() throws {
        try dbWriter.write { db in
            try db.execute(sql: "DELETE FROM clip_items WHERE isPinned = 0;")
        }
    }

    public func deleteAllClips() throws {
        try dbWriter.write { db in
            try db.execute(sql: "DELETE FROM clip_items;")
            try db.execute(sql: "DELETE FROM clip_items_fts;")
        }
        try? optimizeDatabase()
    }

    // MARK: - Maintenance & Optimization

    /// Runs automated retention and capacity pruning.
    /// Pinned clips are NEVER deleted automatically.
    @discardableResult
    public func performCleanup() throws -> Int {
        try dbWriter.write { db in
            var deletedTotal = 0

            // 1. Time-based retention (if retentionDays > 0)
            let retentionSql = """
            DELETE FROM clip_items
            WHERE isPinned = 0
              AND (SELECT retentionDays FROM app_settings WHERE id = 1) > 0
              AND updatedAt < datetime('now', '-' || (SELECT retentionDays FROM app_settings WHERE id = 1) || ' days');
            """
            try db.execute(sql: retentionSql)
            deletedTotal += db.changesCount

            // 2. Capacity-based limit (if maxHistory > 0)
            let capacitySql = """
            DELETE FROM clip_items
            WHERE isPinned = 0
              AND (SELECT maxHistory FROM app_settings WHERE id = 1) > 0
              AND id NOT IN (
                  SELECT id FROM clip_items
                  WHERE isPinned = 0
                  ORDER BY updatedAt DESC
                  LIMIT (SELECT maxHistory FROM app_settings WHERE id = 1)
              );
            """
            try db.execute(sql: capacitySql)
            deletedTotal += db.changesCount

            return deletedTotal
        }
    }

    public func optimizeDatabase() throws {
        try dbWriter.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE);")
            try db.execute(sql: "PRAGMA optimize;")
        }
    }

    // MARK: - Settings

    public func fetchSettings() throws -> AppSettings {
        try dbWriter.read { db in
            try AppSettings.fetchOne(db, key: AppSettings.primaryKeyId) ?? AppSettings.default
        }
    }

    public func updateSettings(_ settings: AppSettings) throws {
        try dbWriter.write { db in
            var mutable = settings
            mutable.id = AppSettings.primaryKeyId
            try mutable.save(db)
        }
    }

    // MARK: - Stats

    public func getDatabaseStats() throws -> DatabaseStats {
        // Attempt a passive WAL checkpoint outside of transaction
        dbWriter.writeWithoutTransaction { db in
            try? db.execute(sql: "PRAGMA wal_checkpoint(PASSIVE);")
        }

        let (total, pinned): (Int, Int) = try dbWriter.read { db in
            let totalCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clip_items;") ?? 0
            let pinnedCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clip_items WHERE isPinned = 1;") ?? 0
            return (totalCount, pinnedCount)
        }

        var fileSize: Int64 = 0
        if let path = dbPath {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int64 {
                fileSize = size
                // Add WAL file size if present
                if let walAttrs = try? FileManager.default.attributesOfItem(atPath: path + "-wal"),
                   let walSize = walAttrs[.size] as? Int64 {
                    fileSize += walSize
                }
            }
        }

        return DatabaseStats(totalClips: total, pinnedClips: pinned, fileSizeBytes: fileSize)
    }

    // MARK: - Reactive Observation Helper

    public func makeClipsObservation(
        searchQuery: @escaping @Sendable () -> String,
        pinnedOnly: @escaping @Sendable () -> Bool,
        limit: Int = 100
    ) -> ValueObservation<ValueReducers.Fetch<[ClipItem]>> {
        ValueObservation.tracking { db in
            let query = searchQuery().trimmingCharacters(in: .whitespacesAndNewlines)
            let isPinnedOnly = pinnedOnly()
            if query.isEmpty {
                if isPinnedOnly {
                    let sql = """
                    SELECT * FROM clip_items
                    WHERE isPinned = 1
                    ORDER BY updatedAt DESC
                    LIMIT ?;
                    """
                    return try ClipItem.fetchAll(db, sql: sql, arguments: [limit])
                } else {
                    let sql = """
                    SELECT * FROM clip_items
                    ORDER BY isPinned DESC, updatedAt DESC
                    LIMIT ?;
                    """
                    return try ClipItem.fetchAll(db, sql: sql, arguments: [limit])
                }
            } else {
                let sanitized = Self.sanitizeFTS5Query(query)
                let sql = """
                SELECT c.*
                FROM clip_items c
                JOIN clip_items_fts f ON c.id = f.rowid
                WHERE clip_items_fts MATCH ?
                  AND (? = 0 OR c.isPinned = 1)
                ORDER BY c.isPinned DESC, c.updatedAt DESC
                LIMIT ?;
                """
                return try ClipItem.fetchAll(db, sql: sql, arguments: [sanitized, isPinnedOnly ? 1 : 0, limit])
            }
        }
    }

    public func makeSettingsObservation() -> ValueObservation<ValueReducers.Fetch<AppSettings>> {
        ValueObservation.tracking { db in
            try AppSettings.fetchOne(db, key: AppSettings.primaryKeyId) ?? AppSettings.default
        }
    }
}

public struct DatabaseError: LocalizedError, Sendable {
    public let message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}
