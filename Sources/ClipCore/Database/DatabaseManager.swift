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
            try db.execute(sql: "PRAGMA cache_size = -1024;")   // Cap SQLite cache at strictly 1 MB
            try db.execute(sql: "PRAGMA temp_store = MEMORY;")
            try db.execute(sql: "PRAGMA mmap_size = 16777216;") // 16 MB memory-mapped read window
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
            try db.execute(sql: "PRAGMA cache_size = -1024;")
            try db.execute(sql: "PRAGMA temp_store = MEMORY;")
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
        fileURL: String? = nil,
        thumbnailFilename: String? = nil
    ) throws -> ClipItem {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DatabaseError(message: "Cannot save empty clip")
        }

        let hash = ClipItem.computeHash(for: trimmed)
        let charCount = trimmed.count
        let lineCount = ClipItem.computeLineCount(for: trimmed)
        let preview = String(trimmed.prefix(150))
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
                previewText, thumbnailFilename,
                createdAt, updatedAt
            ) VALUES (?, ?, ?, ?, ?, ?, 1, 0, ?, ?, ?, ?, ?, ?, ?, ?)
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
                fileURL = coalesce(excluded.fileURL, clip_items.fileURL),
                previewText = coalesce(excluded.previewText, clip_items.previewText),
                thumbnailFilename = coalesce(excluded.thumbnailFilename, clip_items.thumbnailFilename)
            RETURNING *;
            """
            guard let item = try ClipItem.fetchOne(
                db,
                sql: sql,
                arguments: [trimmed, hash, charCount, lineCount, sourceAppBundleId, sourceAppName, formatType, storedRtfData, htmlContent, fileURL, preview, thumbnailFilename, now, now]
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

    public func fetchClip(id: Int64) throws -> ClipItem? {
        try dbWriter.read { db in
            try ClipItem.fetchOne(db, sql: "SELECT * FROM clip_items WHERE id = ?;", arguments: [id])
        }
    }

    public func fetchClip(hash: String) throws -> ClipItem? {
        try dbWriter.read { db in
            try ClipItem.fetchOne(db, sql: "SELECT * FROM clip_items WHERE contentHash = ?;", arguments: [hash])
        }
    }

    public func mostRecentClip() throws -> ClipItem? {
        try dbWriter.read { db in
            try ClipItem.fetchOne(db, sql: "SELECT * FROM clip_items ORDER BY updatedAt DESC, id DESC LIMIT 1;")
        }
    }

    // MARK: - Keyset Pagination (Ultra-low memory list projection)

    /// Fetches lightweight `ClipListSummary` rows, pinned first, then most recently used.
    /// Pass the last row of the previous page as `after` to get the next page.
    /// Paging on (isPinned, updatedAt, id) keeps rows unique across pages.
    public func fetchNextPage(
        after cursor: ClipListSummary? = nil,
        searchQuery: String = "",
        pinnedOnly: Bool = false,
        limit: Int = 25
    ) throws -> [ClipListSummary] {
        try dbWriter.read { db in
            let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            let columns = """
                c.id, coalesce(c.previewText, substr(c.content, 1, 150)) as previewText,
                c.formatType, c.sourceAppBundleId, c.sourceAppName,
                c.isPinned, c.copyCount, c.charCount, c.lineCount,
                c.createdAt, c.updatedAt, c.thumbnailFilename, c.fileURL
            """
            var sql: String
            var arguments: [DatabaseValueConvertible] = []
            if trimmed.isEmpty {
                sql = "SELECT \(columns) FROM clip_items c WHERE (? = 0 OR c.isPinned = 1)"
                arguments.append(pinnedOnly ? 1 : 0)
            } else {
                sql = """
                SELECT \(columns) FROM clip_items c
                JOIN clip_items_fts f ON c.id = f.rowid
                WHERE clip_items_fts MATCH ? AND (? = 0 OR c.isPinned = 1)
                """
                arguments.append(Self.sanitizeFTS5Query(trimmed))
                arguments.append(pinnedOnly ? 1 : 0)
            }
            if let cursor, let id = cursor.id {
                sql += " AND (c.isPinned, c.updatedAt, c.id) < (?, ?, ?)"
                arguments.append(cursor.isPinned ? 1 : 0)
                arguments.append(cursor.updatedAt)
                arguments.append(id)
            }
            sql += " ORDER BY c.isPinned DESC, c.updatedAt DESC, c.id DESC LIMIT ?;"
            arguments.append(limit)
            return try ClipListSummary.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        }
    }

    /// Reclaims transient SQLite memory when popover closes via PRAGMA shrink_memory
    public func shrinkMemory() {
        try? dbWriter.write { db in
            try? db.execute(sql: "PRAGMA shrink_memory;")
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

    /// Marks a clip as just used (moves it to the top) without rewriting its content.
    public func touchClip(id: Int64) throws {
        try dbWriter.write { db in
            try db.execute(sql: "UPDATE clip_items SET updatedAt = ?, copyCount = copyCount + 1 WHERE id = ?;", arguments: [Date(), id])
        }
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
        let deleted = try dbWriter.write { db in
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
        sweepOrphanedFiles()
        return deleted
    }

    /// Deletes blob and thumbnail files that no clip points to any more
    /// (left behind by deletes, history pruning and "Clear").
    /// Files younger than 10 minutes are kept, so a clip being saved right now is never affected.
    public func sweepOrphanedFiles() {
        guard dbPath != nil else { return } // in-memory test databases don't own the shared folders
        let refs: (blobs: Set<String>, thumbs: Set<String>)
        do {
            refs = try dbWriter.read { db in
                var blobs = Set<String>()
                let blobRows = try Data.fetchAll(db, sql: "SELECT rtfData FROM clip_items WHERE rtfData IS NOT NULL AND length(rtfData) < 128;")
                for data in blobRows {
                    if let s = String(data: data, encoding: .utf8), s.hasPrefix("blob://") {
                        blobs.insert(String(s.dropFirst(7)) + ".bin")
                    }
                }
                let thumbs = Set(try String.fetchAll(db, sql: "SELECT thumbnailFilename FROM clip_items WHERE thumbnailFilename IS NOT NULL;"))
                return (blobs, thumbs)
            }
        } catch {
            return
        }

        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-600)
        func sweep(_ dir: URL, keep: Set<String>) {
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
            for file in files where !keep.contains(file.lastPathComponent) {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantFuture
                if modified < cutoff { try? fm.removeItem(at: file) }
            }
        }
        sweep(ClipBlobManager.shared.blobsDirectoryURL, keep: refs.blobs)
        sweep(ThumbnailService.thumbnailsDirectoryURL, keep: refs.thumbs)
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
